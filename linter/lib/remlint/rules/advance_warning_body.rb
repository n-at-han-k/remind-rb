# frozen_string_literal: true

require_relative "../rule"

module RemLint
  module Rules
    # Reminders that arrive early without saying so.
    #
    # A delta makes a reminder start appearing before the day it is about, and
    # a time makes it arrive before the hour. Neither changes the body. So
    #
    #   REM 16 July ++10 MSG Jane's birthday.
    #
    # prints `Jane's birthday.` on the 8th of July, with nothing to say the
    # birthday is eight days off, and reads exactly like a birthday today.
    # `%b` is the idiomatic fix -- "in 8 days' time" -- and `%2` or `%3` is its
    # equivalent for a time.
    #
    # Off by default, and it will fire on plenty of correct files: an advance
    # warning whose body already reads naturally in both places is fine, and
    # only the author can say. Turning it on is worth it for a file being
    # written rather than one being inherited.
    #
    # The paired rule is `CalendarTextLimited`, which asks you to fence the
    # relative phrase in `%"…%"` so it does not follow the reminder into a
    # calendar box.
    class AdvanceWarningBody < Rule
      # `%a` to `%l` and friends all say something about *when*; these are the
      # ones that say how far away it is.
      RELATIVE = /%\*?[abcefghijkluv]/i

      TIME_SUBSTITUTION = /%\*?[0-9@#]/

      DELTA = /(?<!\S)[+-]{1,2}\d+(?!\S)/

      def self.enabled_by_default?
        false
      end

      def self.default_severity
        "info"
      end

      def self.description
        "A reminder with a delta or a time whose body never says when the event is."
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

          check_delta(command, trigger, body)
          check_time(command, trigger, body)
        end

        def check_delta(command, trigger, body)
          if delta?(command, trigger) && !body.match?(RELATIVE)
            offend_at(
              command.logical_line,
              trigger.body.offset,
              "this reminder has a delta, so it appears days before the event, but the " \
              "body never says how far off it is; `%b` reads as \"in 8 days' time\"",
            )
          end
        end

        def check_time(command, trigger, body)
          if trigger.include?("AT") && !body.match?(TIME_SUBSTITUTION) && !body.match?(RELATIVE)
            offend_at(
              command.logical_line,
              trigger.body.offset,
              "this reminder has an `AT`, so the queued copy arrives before the event, " \
              "but the body never mentions the time; `%2` or `%3` says when",
            )
          end
        end

        # A delta is written in the trigger, before the body.
        def delta?(command, trigger)
          head = command.text[0...trigger.body.offset].to_s

          head.match?(DELTA)
        end
    end
  end
end

__END__

require_relative "../document"

describe "RemLint::Rules::AdvanceWarningBody" do
  lint = proc do |text|
    source = RemLint::Source.new(path: "t.rem", text: text)

    RemLint::Rules::AdvanceWarningBody.new.run(RemLint::Document.new(source))
  end

  messages = proc { |text| lint.(text).map(&:message) }

  it "is off unless the configuration asks for it" do
    RemLint::Rules::AdvanceWarningBody.enabled_by_default?.should.be.false
  end

  describe "deltas" do
    it "reports a body that never says how far off the event is" do
      messages.("REM 16 July ++10 MSG Jane's birthday.\n").first.should.match(
        /the body never says how far off it is/,
      )
    end

    it "accepts a body that uses %b" do
      lint.("REM 16 July ++10 MSG Jane's birthday %b.\n").should.be.empty
    end

    it "accepts a body that uses another relative substitution" do
      lint.("REM 16 July ++10 MSG Jane's birthday %c.\n").should.be.empty
    end

    it "accepts a single-sign delta with a relative substitution" do
      lint.("REM 16 July +10 MSG Jane's birthday %b.\n").should.be.empty
    end

    it "says nothing about a reminder with no delta" do
      lint.("REM 16 July MSG Jane's birthday.\n").should.be.empty
    end

    it "does not read a delta out of the body" do
      lint.("REM 16 July MSG the score was +10 points\n").should.be.empty
    end
  end

  describe "times" do
    it "reports an AT reminder whose body never mentions the time" do
      messages.("REM Tue AT 15:00 MSG Staff meeting\n").first.should.match(
        /the body never mentions the time/,
      )
    end

    it "accepts a body that uses %2" do
      lint.("REM Tue AT 15:00 MSG Staff meeting at %2\n").should.be.empty
    end

    it "accepts a body that uses %3 or %@" do
      lint.("REM Tue AT 15:00 MSG Meeting %3\n").should.be.empty
      lint.("REM Tue AT 15:00 MSG Meeting %@\n").should.be.empty
    end

    it "says nothing about a reminder with no AT" do
      lint.("REM Tue MSG Staff meeting\n").should.be.empty
    end
  end

  it "says nothing about a SATISFY body, which is an expression" do
    lint.("REM 16 July ++10 SATISFY [1]\n").should.be.empty
  end

  it "says nothing about comments" do
    lint.("# REM 16 July ++10 MSG Jane's birthday.\n").should.be.empty
  end

  it "reports at info severity" do
    lint.("REM 16 July ++10 MSG hi\n").first.severity.should == "info"
  end
end
