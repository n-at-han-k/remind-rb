# frozen_string_literal: true

require_relative "../rule"

module RemLint
  module Rules
    # Numeric clause arguments outside the range Remind accepts.
    #
    # Four clauses take a bounded number and all four bounds are in the C:
    #
    #   AT hh:mm        0-23 and 0-59
    #   DURATION hh:mm  minutes 0-59; the hour is unbounded
    #   PRIORITY n      0-9999 (`ParsePriority`, src/dorem.c)
    #   MAX-OVERDUE n   days past due, so a positive count
    #
    # Remind rejects each of them, but only when the line is reached. For a
    # reminder that is the day it triggers, which for an annual one is up to a
    # year after the typo was made.
    #
    # `DURATION` deliberately has no hour ceiling. A duration is a *length*,
    # not a time of day: Remind's own `tests/test3.rem` writes
    # `DURATION 24:45` and `DURATION 48:45` for events running over more than
    # one day, and Remind accepts them. Only the minutes are bounded.
    #
    # `PRIORITY -1` is worth a word: `ParsePriority` starts with `isdigit`, so
    # a minus sign is `Expecting number` rather than an out-of-range value, and
    # the message says so rather than talking about the range.
    class ClauseValueRange < Rule
      MAX_HOUR = 23
      MAX_MINUTE = 59
      MAX_PRIORITY = 9999

      # Only `AT` is a time of day, so only `AT` has an hour ceiling.
      BOUNDED_HOUR = %w[AT].freeze

      TIME_CLAUSES = %w[AT DURATION].freeze

      # `15:00`, `15.00` -- Remind takes either separator.
      TIME = /\A(?<hour>\d{1,2})[:.](?<minute>\d{1,2})\z/i

      AM_PM = /\A(?<hour>\d{1,2})([:.](?<minute>\d{1,2}))?\s*(?<half>am|pm)\z/i

      def self.default_severity
        "error"
      end

      def self.description
        "An AT, DURATION, PRIORITY or MAX-OVERDUE value outside its range."
      end

      def check
        document.code_commands.each do |command|
          trigger = document.trigger_for(command)

          TIME_CLAUSES.each { |name| check_time(command, trigger.find(name)) }
          check_priority(command, trigger.find("PRIORITY"))
          check_max_overdue(command, trigger.find("MAX-OVERDUE"))
        end
      end

      private

        # The literal word after a clause keyword, or nil when the argument is
        # computed and so not this rule's to judge.
        def argument(command, clause)
          if clause
            rest = command.text[clause.end_offset..].to_s

            rest.strip[/\A\S+/]
          end
        end

        def check_time(command, clause)
          text = argument(command, clause)
          match = text && (text.match(TIME) || text.match(AM_PM))

          if match
            report_time(command, clause, match)
          end
        end

        def report_time(command, clause, match)
          hour = match[:hour].to_i
          minute = match[:minute].to_i
          if am_pm?(match)
            limit = 12
          else
            limit = MAX_HOUR
          end

          if BOUNDED_HOUR.include?(clause.name) && hour > limit
            offend_at(command.logical_line, clause.offset, hour_message(clause, hour, limit))
          elsif minute > MAX_MINUTE
            offend_at(command.logical_line, clause.offset, minute_message(clause, minute))
          end
        end

        def am_pm?(match)
          match.names.include?("half") && !match[:half].nil?
        end

        def hour_message(clause, hour, limit)
          "`#{clause.name} #{hour}:...` has an hour of #{hour}; Remind accepts 0 to #{limit}"
        end

        def minute_message(clause, minute)
          "`#{clause.name}` has a minute of #{minute}; Remind accepts 0 to #{MAX_MINUTE}"
        end

        def check_priority(command, clause)
          text = argument(command, clause)

          if text&.match?(/\A-\d+\z/)
            offend_at(
              command.logical_line,
              clause.offset,
              "`PRIORITY #{text}` is rejected as `Expecting number`; " \
              "ParsePriority reads digits only, so a minus never reaches the range check",
            )
          elsif text&.match?(/\A\d+\z/) && text.to_i > MAX_PRIORITY
            offend_at(
              command.logical_line,
              clause.offset,
              "`PRIORITY #{text}` is outside 0 to #{MAX_PRIORITY}",
            )
          end
        end

        def check_max_overdue(command, clause)
          text = argument(command, clause)

          if text&.match?(/\A-?\d+\z/) && text.to_i < 1
            offend_at(
              command.logical_line,
              clause.offset,
              "`MAX-OVERDUE #{text}` counts days past the due date, so it has to be " \
              "positive; #{text} switches the nagging off rather than configuring it",
            )
          end
        end
    end
  end
end

__END__

require_relative "../document"

describe "RemLint::Rules::ClauseValueRange" do
  lint = proc do |text|
    source = RemLint::Source.new(path: "t.rem", text: text)

    RemLint::Rules::ClauseValueRange.new.run(RemLint::Document.new(source))
  end

  messages = proc { |text| lint.(text).map(&:message) }

  describe "AT times" do
    it "accepts a valid time" do
      lint.("REM Tue AT 15:00 MSG hi\n").should.be.empty
      lint.("REM Tue AT 0:00 MSG hi\n").should.be.empty
      lint.("REM Tue AT 23:59 MSG hi\n").should.be.empty
    end

    it "accepts the dot separator" do
      lint.("REM Tue AT 15.00 MSG hi\n").should.be.empty
    end

    it "reports an hour past 23" do
      messages.("REM Tue AT 25:00 MSG hi\n").first.should.match(/an hour of 25; Remind accepts 0 to 23/)
    end

    it "reports a minute past 59" do
      messages.("REM Tue AT 9:70 MSG hi\n").first.should.match(/a minute of 70/)
    end

    it "accepts an am/pm time" do
      lint.("REM Tue AT 3:00PM MSG hi\n").should.be.empty
      lint.("REM Tue AT 11:59am MSG hi\n").should.be.empty
    end

    it "reports an am/pm hour past 12" do
      messages.("REM Tue AT 13:00PM MSG hi\n").first.should.match(/Remind accepts 0 to 12/)
    end
  end

  describe "DURATION" do
    it "accepts a valid duration" do
      lint.("REM Tue AT 15:00 DURATION 1:30 MSG hi\n").should.be.empty
    end

    it "reports a minute past 59" do
      messages.("REM Tue AT 15:00 DURATION 1:75 MSG hi\n").first.should.match(/`DURATION`/)
    end

    it "accepts an hour past 23, because a duration is a length" do
      # tests/test3.rem writes DURATION 24:45 and DURATION 48:45; Remind
      # accepts both -- the event simply runs over more than one day.
      lint.("REM Tue AT 11:00 DURATION 24:45 MSG hi\n").should.be.empty
      lint.("REM Tue AT 11:00 DURATION 48:45 MSG hi\n").should.be.empty
    end
  end

  describe "PRIORITY" do
    it "accepts the range" do
      lint.("REM Tue PRIORITY 0 MSG hi\n").should.be.empty
      lint.("REM Tue PRIORITY 9999 MSG hi\n").should.be.empty
    end

    it "reports a value past 9999" do
      messages.("REM Tue PRIORITY 10000 MSG hi\n").first.should ==
        "`PRIORITY 10000` is outside 0 to 9999"
    end

    it "explains that a negative is a parse error, not a range one" do
      messages.("REM Tue PRIORITY -1 MSG hi\n").first.should.match(
        /rejected as `Expecting number`/,
      )
    end
  end

  describe "MAX-OVERDUE" do
    it "accepts a positive count" do
      lint.("REM Tue MAX-OVERDUE 5 MSG hi\n").should.be.empty
    end

    it "reports zero" do
      messages.("REM Tue MAX-OVERDUE 0 MSG hi\n").first.should.match(/has to be positive/)
    end

    it "reports a negative" do
      messages.("REM Tue MAX-OVERDUE -3 MSG hi\n").length.should == 1
    end
  end

  describe "arguments it cannot judge" do
    it "says nothing about a computed time" do
      lint.("REM Tue AT [sunset()] MSG hi\n").should.be.empty
    end

    it "says nothing about a computed priority" do
      lint.("REM Tue PRIORITY [p] MSG hi\n").should.be.empty
    end
  end

  it "does not read a time out of a message body" do
    lint.("REM Tue MSG Meeting at 25:00 in the old money\n").should.be.empty
  end

  it "says nothing about comments" do
    lint.("# REM Tue AT 25:00 MSG hi\n").should.be.empty
  end

  it "reports at error severity" do
    lint.("REM Tue AT 25:00 MSG hi\n").first.severity.should == "error"
  end
end
