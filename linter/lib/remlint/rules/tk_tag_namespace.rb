# frozen_string_literal: true

require_relative "../rule"

module RemLint
  module Rules
    # A hand-written `TAG` in TkRemind's namespace.
    #
    # TkRemind finds the `REM` command it is about to edit or delete by its
    # tag, and it names its own tags `TKTAG` followed by a number. A
    # hand-written tag in that shape collides, and TkRemind then edits or
    # deletes the wrong reminder.
    #
    # There is no error and no warning. The user clicks a reminder in the GUI,
    # a different one changes, and nothing anywhere says why -- which makes it
    # a data-loss bug with no diagnostic attached.
    class TkTagNamespace < Rule
      RESERVED = /\ATKTAG\d+\z/i

      def self.default_severity
        "warning"
      end

      def self.description
        "A TAG in TkRemind's TKTAGn namespace, which makes the GUI edit the wrong reminder."
      end

      def check
        document.code_commands.each do |command|
          document.trigger_for(command).clauses.each do |clause|
            if clause.name == "TAG"
              check_tag(command, clause)
            end
          end
        end
      end

      private

        def check_tag(command, clause)
          value = tag_value(command, clause)

          if value&.match?(RESERVED)
            offend_at(
              command.logical_line,
              clause.offset,
              "`#{value}` is in TkRemind's own `TKTAGn` namespace; it finds the command " \
              "to edit by its tag, so a collision makes the GUI change a different " \
              "reminder with no diagnostic",
            )
          end
        end

        def tag_value(command, clause)
          token = document.tokens_for(command.logical_line)[clause.argument_index]

          case token&.type
          when :string then token.value[1..-2]
          when :name then token.value
          end
        end
    end
  end
end

__END__

require_relative "../document"

describe "RemLint::Rules::TkTagNamespace" do
  lint = proc do |text|
    source = RemLint::Source.new(path: "t.rem", text: text)

    RemLint::Rules::TkTagNamespace.new.run(RemLint::Document.new(source))
  end

  it "reports a quoted tag in the reserved namespace" do
    lint.(%(REM 1 Jan TAG "TKTAG1" MSG hi\n)).first.message.should.match(
      /is in TkRemind's own `TKTAGn` namespace/,
    )
  end

  it "reports an unquoted one" do
    lint.("REM 1 Jan TAG TKTAG42 MSG hi\n").length.should == 1
  end

  it "matches the prefix case-insensitively" do
    lint.("REM 1 Jan TAG tktag7 MSG hi\n").length.should == 1
  end

  it "accepts an ordinary tag" do
    lint.(%(REM 1 Jan TAG "birthday" MSG hi\n)).should.be.empty
  end

  it "accepts a tag that merely starts with the prefix" do
    # TkRemind's are the prefix plus digits and nothing else.
    lint.(%(REM 1 Jan TAG "TKTAGGED" MSG hi\n)).should.be.empty
  end

  it "accepts a tag with no digits" do
    lint.(%(REM 1 Jan TAG "TKTAG" MSG hi\n)).should.be.empty
  end

  it "says nothing about a reminder with no TAG" do
    lint.("REM 1 Jan MSG hi\n").should.be.empty
  end

  it "explains why it matters" do
    lint.("REM 1 Jan TAG TKTAG1 MSG hi\n").first.message.should.match(
      /change a different reminder with no diagnostic/,
    )
  end

  it "says nothing about comments" do
    lint.("# REM 1 Jan TAG TKTAG1 MSG hi\n").should.be.empty
  end

  it "reports at warning severity" do
    lint.("REM 1 Jan TAG TKTAG1 MSG hi\n").first.severity.should == "warning"
  end
end
