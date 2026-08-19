# frozen_string_literal: true

require_relative "../rule"

module RemLint
  module Rules
    # A relative phrase that follows the reminder into a calendar box.
    #
    # `%"…%"` marks the part of a body that belongs in a calendar. Outside the
    # marks, text appears in Agenda Mode only. The distinction matters most for
    # exactly the substitutions `AdvanceWarningBody` asks you to add:
    #
    #   REM 16 July ++10 MSG %"Jane's birthday%" %b.
    #
    # In Agenda Mode that reads "Jane's birthday in 8 days' time". In a
    # calendar it is printed in the box for 16 July, where "in 8 days' time" is
    # not merely redundant but wrong -- the box already says which day it is.
    #
    # So this is the second half of a pair: one rule asks for `%b`, this one
    # asks you to fence it. Off by default, like its sibling, and for the same
    # reason: a file that is never rendered as a calendar does not need it.
    class CalendarTextLimited < Rule
      RELATIVE = /%\*?[abcefghijkluv]/i

      MARKER = '%"'

      def self.enabled_by_default?
        false
      end

      def self.default_severity
        "info"
      end

      def self.description
        "A relative-date substitution in a body with no %\" ... %\" calendar limit."
      end

      def check
        document.code_commands.each do |command|
          trigger = document.trigger_for(command)

          if trigger.text_body?
            check_body(command, trigger)
          end
        end
      end

      private

        def check_body(command, trigger)
          body = command.text[trigger.body_offset..].to_s
          match = body.match(RELATIVE)

          if match && !body.include?(MARKER)
            offend_at(
              command.logical_line,
              trigger.body_offset + match.begin(0),
              "`#{match[0]}` says how far off the event is, which is right in Agenda " \
              "Mode and wrong in a calendar box; fence the name in `%\"…%\"` so only " \
              "that reaches the calendar",
            )
          end
        end
    end
  end
end

__END__

require_relative "../document"

describe "RemLint::Rules::CalendarTextLimited" do
  lint = proc do |text|
    source = RemLint::Source.new(path: "t.rem", text: text)

    RemLint::Rules::CalendarTextLimited.new.run(RemLint::Document.new(source))
  end

  messages = proc { |text| lint.(text).map(&:message) }

  it "is off unless the configuration asks for it" do
    RemLint::Rules::CalendarTextLimited.enabled_by_default?.should.be.false
  end

  it "reports a relative substitution with no calendar limit" do
    messages.("REM 16 July ++10 MSG Jane's birthday %b.\n").first.should.match(
      /wrong in a calendar box/,
    )
  end

  it "names the substitution it found" do
    messages.("REM 16 July ++10 MSG Jane's birthday %b.\n").first.should.match(/`%b` says/)
  end

  it "accepts a body that fences the name" do
    lint.(%(REM 16 July ++10 MSG %"Jane's birthday%" %b.\n)).should.be.empty
  end

  it "accepts a body with no relative substitution at all" do
    lint.("REM 16 July MSG Jane's birthday.\n").should.be.empty
  end

  it "reports only once per body" do
    lint.("REM 16 July ++10 MSG %b and %c\n").length.should == 1
  end

  it "points at the substitution" do
    text = "REM 16 July ++10 MSG Jane %b.\n"

    lint.(text).first.column.should == text.index("%b") + 1
  end

  it "says nothing about a SATISFY body" do
    lint.("REM 16 July SATISFY [1]\n").should.be.empty
  end

  it "says nothing about comments" do
    lint.("# REM 16 July ++10 MSG Jane %b.\n").should.be.empty
  end

  it "reports at info severity" do
    lint.("REM 16 July ++10 MSG Jane %b.\n").first.severity.should == "info"
  end
end
