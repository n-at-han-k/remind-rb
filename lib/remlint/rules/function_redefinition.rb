# frozen_string_literal: true

require_relative "../rule"
require_relative "../vocabulary"

module RemLint
  module Rules
    # A function defined twice without saying so.
    #
    # Remind warns about a redefinition itself, and gives you a way to say the
    # redefinition is deliberate: `FSET - name(...)` sets
    # `suppress_redefined_function_warning` and the warning goes away
    # (src/userfns.c). So this rule is not telling you something Remind would
    # not -- it is telling you where the `-` goes.
    #
    # Worth having anyway, because the two definitions are usually a long way
    # apart. Remind's own `tests/test.rem` defines `g(x, y)` on line 356 and
    # redefines it as `g(x)` on line 1545, and every call in between is
    # checked against a different function than the one the reader is looking
    # at.
    #
    # A definition inside a `PUSH-FUNCS` block is left alone: pushing the
    # function table is exactly how you say "this redefinition is scoped", and
    # Remind skips its own warning for a pushed function too
    # (`!existing->been_pushed`).
    class FunctionRedefinition < Rule
      # `FSET name(args)` and the `FSET - name(args)` that suppresses the
      # warning.
      DEFINITION = /\A(?<deliberate>-\s*)?(?<name>[A-Za-z_]\w*)\s*\(/

      def self.default_severity
        "warning"
      end

      def self.description
        "A function redefined without the FSET - form that says so."
      end

      def check
        seen = {}
        pushed = 0

        document.code_commands.each do |command|
          pushed = track(command, pushed)

          if command.keyword?("FSET") && pushed.zero?
            check_definition(command, seen)
          end
        end
      end

      private

        def track(command, pushed)
          if command.keyword?("PUSH-FUNCS")
            pushed + 1
          elsif command.keyword?("POP-FUNCS")
            [pushed - 1, 0].max
          else
            pushed
          end
        end

        def check_definition(command, seen)
          match = command.args.match(DEFINITION)

          if match
            record(command, match, seen)
          end
        end

        def record(command, match, seen)
          name = match[:name].downcase
          first = seen[name]

          if first && !match[:deliberate]
            offend(command.line, message(match[:name], first), column: command.keyword_column)
          end

          seen[name] ||= command.line
        end

        def message(name, first)
          "`#{name}` was already defined on line #{first}; write `FSET - #{name}(...)` " \
          "to say the redefinition is deliberate and silence Remind's warning"
        end
    end
  end
end

__END__

require_relative "../document"

describe "RemLint::Rules::FunctionRedefinition" do
  lint = proc do |text|
    source = RemLint::Source.new(path: "t.rem", text: text)

    RemLint::Rules::FunctionRedefinition.new.run(RemLint::Document.new(source))
  end

  messages = proc { |text| lint.(text).map(&:message) }

  it "reports a second definition of the same name" do
    messages.("FSET g(a, b) a + b\nFSET g(a) a\n").first.should ==
      "`g` was already defined on line 1; write `FSET - g(...)` to say the redefinition " \
      "is deliberate and silence Remind's warning"
  end

  it "reports the second and not the first" do
    lint.("FSET g(a) a\nFSET g(b) b\n").map(&:line).should == [2]
  end

  it "reports each redefinition after the first" do
    lint.("FSET g(a) a\nFSET g(b) b\nFSET g(c) c\n").map(&:line).should == [2, 3]
  end

  it "accepts the FSET - form that says it is deliberate" do
    lint.("FSET g(a) a\nFSET - g(b) b\n").should.be.empty
  end

  it "accepts the deliberate form written without a space" do
    lint.("FSET g(a) a\nFSET -g(b) b\n").should.be.empty
  end

  it "matches the name case-insensitively, as Remind does" do
    lint.("FSET g(a) a\nFSET G(b) b\n").length.should == 1
  end

  it "accepts two different functions" do
    lint.("FSET g(a) a\nFSET h(b) b\n").should.be.empty
  end

  it "accepts a redefinition inside a PUSH-FUNCS block" do
    # Pushing the table is how a scoped redefinition is said, and Remind
    # skips its own warning for a pushed function too.
    lint.("FSET g(a) a\nPUSH-FUNCS\nFSET g(b) b\nPOP-FUNCS\n").should.be.empty
  end

  it "resumes checking after the block closes" do
    lint.("FSET g(a) a\nPUSH-FUNCS\nPOP-FUNCS\nFSET g(b) b\n").length.should == 1
  end

  it "points at the keyword" do
    lint.("FSET g(a) a\n   FSET g(b) b\n").first.column.should == 4
  end

  it "says nothing about comments" do
    lint.("FSET g(a) a\n# FSET g(b) b\n").should.be.empty
  end

  it "says nothing about a call that looks like a definition" do
    lint.("FSET g(a) a\nMSG [g(1)]\n").should.be.empty
  end

  it "reports at warning severity" do
    lint.("FSET g(a) a\nFSET g(b) b\n").first.severity.should == "warning"
  end
end
