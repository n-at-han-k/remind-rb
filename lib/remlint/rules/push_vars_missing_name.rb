# frozen_string_literal: true

require_relative "../rule"

module RemLint
  module Rules
    # A variable assigned inside a `PUSH-VARS` block that the `PUSH-VARS` did
    # not name.
    #
    # `PUSH-VARS a b c` saves exactly `a`, `b` and `c`, and `POP-VARS` restores
    # exactly those. An assignment to anything else inside the block survives
    # the `POP` -- which is the one thing the block was written to prevent.
    #
    # The bare `PUSH-VARS` with no names saves *every* variable, so a block
    # written that way is never reported: it cannot leak.
    #
    # Nothing about this is an error, and nothing reports it. The block looks
    # like a scope, reads like a scope, and quietly is not one for the variable
    # somebody added later.
    class PushVarsMissingName < Rule
      ASSIGNMENT = /\A(?<name>[A-Za-z_]\w*)\b/

      def self.default_severity
        "warning"
      end

      def self.description
        "A variable SET inside a PUSH-VARS block that the PUSH-VARS never named."
      end

      def check
        @stack = []

        document.code_commands.each do |command|
          dispatch(command)
        end
      end

      private

        def dispatch(command)
          if command.keyword?("PUSH-VARS")
            @stack.push(saved(command))
          elsif command.keyword?("POP-VARS")
            @stack.pop
          elsif command.keyword?("SET", "UNSET")
            check_assignment(command)
          end
        end

        # The names the PUSH-VARS listed, or nil for the bare form that saves
        # everything.
        def saved(command)
          names = command.args.strip.split(/[\s,]+/).reject(&:empty?)

          if names.empty?
            nil
          else
            names.map(&:downcase)
          end
        end

        def check_assignment(command)
          frame = @stack.last
          name = assigned_name(command)

          if !@stack.empty? && frame && name && !frame.include?(name.downcase)
            offend(command.line, message(name, frame), column: command.keyword_column)
          end
        end

        # `SET $SysVar` is a different namespace and `POP-VARS` does not carry
        # it, so only ordinary variables are checked.
        def assigned_name(command)
          match = command.args.match(ASSIGNMENT)

          match && match[:name]
        end

        def message(name, saved)
          "`#{name}` is not one of the variables this `PUSH-VARS` saved " \
          "(#{saved.join(', ')}), so the assignment survives the `POP-VARS`"
        end
    end
  end
end

__END__

require_relative "../document"

describe "RemLint::Rules::PushVarsMissingName" do
  lint = proc do |text|
    source = RemLint::Source.new(path: "t.rem", text: text)

    RemLint::Rules::PushVarsMissingName.new.run(RemLint::Document.new(source))
  end

  messages = proc { |text| lint.(text).map(&:message) }

  it "reports an assignment the PUSH-VARS did not name" do
    messages.("PUSH-VARS a\nSET b 1\nPOP-VARS\n").first.should ==
      "`b` is not one of the variables this `PUSH-VARS` saved (a), so the assignment " \
      "survives the `POP-VARS`"
  end

  it "accepts an assignment the PUSH-VARS named" do
    lint.("PUSH-VARS a\nSET a 1\nPOP-VARS\n").should.be.empty
  end

  it "accepts any of several names" do
    lint.("PUSH-VARS a b c\nSET b 1\nSET c 2\nPOP-VARS\n").should.be.empty
  end

  it "accepts names separated by commas" do
    lint.("PUSH-VARS a, b\nSET b 1\nPOP-VARS\n").should.be.empty
  end

  it "matches names case-insensitively" do
    lint.("PUSH-VARS Foo\nSET foo 1\nPOP-VARS\n").should.be.empty
  end

  it "accepts everything inside a bare PUSH-VARS, which saves the lot" do
    lint.("PUSH-VARS\nSET anything 1\nPOP-VARS\n").should.be.empty
  end

  it "says nothing outside a block" do
    lint.("SET b 1\nPUSH-VARS a\nPOP-VARS\nSET c 2\n").should.be.empty
  end

  it "reports an UNSET too" do
    messages.("PUSH-VARS a\nUNSET b\nPOP-VARS\n").length.should == 1
  end

  it "says nothing about a system variable, which POP-VARS does not carry" do
    lint.("PUSH-VARS a\nSET $FormWidth 80\nPOP-VARS\n").should.be.empty
  end

  it "uses the innermost block's list" do
    lint.("PUSH-VARS a\nPUSH-VARS b\nSET b 1\nPOP-VARS\nPOP-VARS\n").should.be.empty
  end

  it "reports against the innermost block only" do
    messages.("PUSH-VARS a\nPUSH-VARS b\nSET a 1\nPOP-VARS\nPOP-VARS\n").length.should == 1
  end

  it "points at the keyword" do
    lint.("PUSH-VARS a\n   SET b 1\nPOP-VARS\n").first.column.should == 4
  end

  it "says nothing about comments" do
    lint.("PUSH-VARS a\n# SET b 1\nPOP-VARS\n").should.be.empty
  end

  it "reports at warning severity" do
    lint.("PUSH-VARS a\nSET b 1\nPOP-VARS\n").first.severity.should == "warning"
  end
end
