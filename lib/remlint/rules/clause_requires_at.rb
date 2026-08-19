# frozen_string_literal: true

require_relative "../rule"

module RemLint
  module Rules
    # Clauses that need a time, on a reminder that has none.
    #
    # `AT` is what gives a reminder a time of day. Two other clauses are only
    # meaningful once it does:
    #
    #   DURATION   a duration with no start time has nothing to be a duration
    #              of, and the back-ends have nowhere to place it
    #   TZ         a bare date cannot be converted between zones -- there is no
    #              instant to convert
    #
    # Both fail in the worst way: the reminder parses, runs, and quietly does
    # something other than what the clause says. `TZ` without `AT` is the one
    # that bites months later, when a reminder fires on a day the author never
    # intended.
    #
    # `AT` is not the only way to get a time, though, and Remind's own
    # `include/lunar-eclipses.rem` is 142 lines of the other way:
    #
    #   REM NOQUEUE [utctolocal('2097-04-26@10:37')] DURATION 196 MSG ...
    #
    # A pasted expression that evaluates to a DATETIME supplies the date *and*
    # the time, so `DURATION` there is correct. Whether `utctolocal(...)`
    # returns a DATETIME is not decidable without running it -- so a trigger
    # containing any bracketed expression is left alone. Same principle as
    # FunctionArity staying quiet about functions it has not seen defined:
    # where the linter cannot know, it says nothing.
    class ClauseRequiresAt < Rule
      REASONS = {
        "DURATION" => "a duration needs a start time",
        "TZ"       => "a bare date has no instant to convert between zones",
      }.freeze

      def self.default_severity
        "error"
      end

      def self.description
        "DURATION or TZ on a reminder with no AT clause."
      end

      def check
        document.code_commands.each do |command|
          check_command(command)
        end
      end

      private

        def check_command(command)
          trigger = document.trigger_for(command)

          unless trigger.include?("AT") || computed_time?(command, trigger)
            report_orphans(command, trigger)
          end
        end

        # Any bracketed expression before the body could be the DATETIME that
        # supplies the time.
        def computed_time?(command, trigger)
          limit = trigger.body_offset || command.text.length

          document.tokens_for(command.logical_line).any? do |token|
            token.type == :lbracket && token.offset < limit
          end
        end

        def report_orphans(command, trigger)
          REASONS.each do |name, reason|
            clause = trigger.find(name)

            if clause
              offend_at(
                command.logical_line,
                clause.offset,
                "`#{name}` without an `AT` clause: #{reason}",
              )
            end
          end
        end
    end
  end
end

__END__

require_relative "../document"

describe "RemLint::Rules::ClauseRequiresAt" do
  lint = proc do |text|
    source = RemLint::Source.new(path: "t.rem", text: text)

    RemLint::Rules::ClauseRequiresAt.new.run(RemLint::Document.new(source))
  end

  messages = proc { |text| lint.(text).map(&:message) }

  describe "DURATION" do
    it "is reported without AT" do
      messages.("REM 1 Jan DURATION 1:00 MSG Meeting\n").first.should.match(/`DURATION` without an `AT`/)
    end

    it "is accepted with AT" do
      lint.("REM 1 Jan AT 15:00 DURATION 1:00 MSG Meeting\n").should.be.empty
    end

    it "is accepted with AT written after it" do
      lint.("REM 1 Jan DURATION 1:00 AT 15:00 MSG Meeting\n").should.be.empty
    end
  end

  describe "TZ" do
    it "is reported without AT" do
      messages.("REM 1 Jan TZ America/Toronto MSG hi\n").first.should.match(/`TZ` without an `AT`/)
    end

    it "is accepted with AT" do
      lint.("REM 1 Jan AT 15:00 TZ America/Toronto MSG hi\n").should.be.empty
    end
  end

  it "reports both clauses on one reminder" do
    messages.("REM 1 Jan DURATION 1:00 TZ UTC MSG hi\n").length.should == 2
  end

  it "points at the offending clause" do
    text = "REM 1 Jan DURATION 1:00 MSG Meeting\n"

    lint.(text).first.column.should == text.index("DURATION") + 1
  end

  describe "what it leaves alone" do
    it "says nothing about a reminder with neither clause" do
      lint.("REM 1 Jan MSG hi\n").should.be.empty
    end

    it "says nothing when the time could come from a pasted expression" do
      # Straight out of include/lunar-eclipses.rem: the DATETIME the expression
      # returns carries the time, so DURATION is correct here.
      text = "REM NOQUEUE [utctolocal('2097-04-26@10:37')] DURATION 196 MSG Eclipse\n"

      lint.(text).should.be.empty
    end

    it "still reports when the bracket is only in the body" do
      # A body expression cannot supply the trigger's time.
      lint.("REM 1 Jan DURATION 1:00 MSG at [place]\n").length.should == 1
    end

    it "does not read the words out of a message body" do
      # `duration` and the zone name are English here, not clauses.
      lint.("REM 1 Jan MSG Confirm the duration with the TZ America/Toronto team\n").should.be.empty
    end

    it "says nothing about comments" do
      lint.("# REM 1 Jan TZ UTC MSG hi\n").should.be.empty
    end
  end

  it "matches abbreviated clause keywords" do
    # DURATION's minimum length is 8, TZ's is 2, AT's is 2.
    lint.("REM 1 Jan AT 15:00 DURATION 1:00 MSG hi\n").should.be.empty
    messages.("REM 1 Jan TZ UTC MSG hi\n").length.should == 1
  end

  it "reports at error severity" do
    lint.("REM 1 Jan TZ UTC MSG hi\n").first.severity.should == "error"
  end

  it "reports the physical line inside a continuation" do
    lint.("REM 1 Jan \\\n    TZ UTC MSG hi\n").first.line.should == 2
  end
end
