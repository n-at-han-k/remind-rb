# frozen_string_literal: true

require_relative "../rule"
require_relative "../date_literal"

module RemLint
  module Rules
    # Repeats that do not repeat what the author meant.
    #
    # A repeat is `*n`: the reminder triggers on its start date and every *n*
    # days after. Two things go wrong with it, and neither is an error.
    #
    # NO START DATE. A repeat counts days from somewhere, and without a fully
    # specified start date there is nothing to count from.
    #
    # A WEEKDAY IN THE TRIGGER. The weekday picks the start date and nothing
    # else -- the recurrence then ignores weekdays entirely. `REM Fri 15 Sep
    # 2025 *10` starts on Friday 19 September and fires every ten days after,
    # on days that are mostly not Fridays. Whatever the `Fri` was for, it was
    # almost certainly not that.
    class RepeatTrigger < Rule
      WEEKDAY_TYPE = "T_WkDay"

      def self.default_severity
        "warning"
      end

      def self.description
        "A *n repeat with no start date, or with a weekday that does not affect it."
      end

      def check
        document.code_commands.each do |command|
          repeat = repeat_token(command)

          if repeat
            check_repeat(command, repeat)
          end
        end
      end

      private

        # `*10` reaches the lexer as `*` then `10`. Only a command that carries
        # a trigger can carry a repeat -- `SET a 3*14` is multiplication.
        def repeat_token(command)
          trigger = document.trigger_for(command)
          limit = trigger.body_offset || command.text.length
          tokens = document.tokens_for(command.logical_line)

          if trigger.triggered?
            tokens.each_index.filter_map { |index| star(tokens, index, limit) }.first
          end
        end

        def star(tokens, index, limit)
          token = tokens[index]
          following = tokens[index + 1]

          if token.type == :other && token.value == "*" &&
             following&.type == :number && token.offset < limit
            token
          end
        end

        def check_repeat(command, repeat)
          tokens = document.tokens_for(command.logical_line)

          unless start_date(tokens)
            offend_at(command.logical_line, repeat.offset, no_start_message)
          end

          weekday = weekday_clause(command)

          if weekday
            offend_at(command.logical_line, weekday.offset, weekday_message(weekday))
          end
        end

        # A fully specified date anywhere in the trigger.
        def start_date(tokens)
          tokens.each_index.any? { |index| DateLiteral.at(tokens, index) }
        end

        def weekday_clause(command)
          document.trigger_for(command).clauses.find do |clause|
            clause.keyword.type == WEEKDAY_TYPE
          end
        end

        def no_start_message
          "a `*n` repeat counts days from a start date, and this trigger has no " \
          "fully specified one to count from"
        end

        def weekday_message(clause)
          "`#{clause.name}` only picks the start date; the `*n` repeat that follows " \
          "counts days and ignores weekdays entirely"
        end
    end
  end
end

__END__

require_relative "../document"

describe "RemLint::Rules::RepeatTrigger" do
  lint = proc do |text|
    source = RemLint::Source.new(path: "t.rem", text: text)

    RemLint::Rules::RepeatTrigger.new.run(RemLint::Document.new(source))
  end

  messages = proc { |text| lint.(text).map(&:message) }

  describe "repeats that are fine" do
    it "accepts a repeat with an ISO start date" do
      lint.("REM 2012-11-07 *14 MSG Garbage\n").should.be.empty
    end

    it "accepts a repeat with a spelled-out start date" do
      lint.("REM 31 October 2012 *14 MSG Paper recycling\n").should.be.empty
    end

    it "accepts a reminder with no repeat at all" do
      lint.("REM Fri MSG hi\n").should.be.empty
      lint.("REM 1 Jan MSG hi\n").should.be.empty
    end
  end

  describe "a repeat with no start date" do
    it "is reported" do
      messages.("REM Mon *14 MSG hi\n").first.should.match(/no fully specified one to count from/)
    end

    it "is reported for a partial date" do
      messages.("REM 1 Jan *14 MSG hi\n").first.should.match(/no fully specified one/)
    end

    it "points at the repeat" do
      text = "REM Mon *14 MSG hi\n"

      lint.(text).map(&:column).should.include(text.index("*14") + 1)
    end
  end

  describe "a weekday with a repeat" do
    it "is reported" do
      # Straight from chapter 4: starts on 19 Sep, then every ten days.
      messages.("REM Fri 15 Sep 2025 *10 MSG Test\n").first.should ==
        "`FRIDAY` only picks the start date; the `*n` repeat that follows counts days " \
        "and ignores weekdays entirely"
    end

    it "points at the weekday" do
      text = "REM Fri 15 Sep 2025 *10 MSG Test\n"

      lint.(text).first.column.should == text.index("Fri") + 1
    end

    it "is not reported without a repeat" do
      lint.("REM Fri 15 Sep 2025 MSG Test\n").should.be.empty
    end

    it "reports both faults when a weekday repeat has no start date" do
      lint.("REM Fri *10 MSG Test\n").length.should == 2
    end
  end

  describe "what it leaves alone" do
    it "does not read a star out of a message body" do
      lint.("REM 2012-11-07 MSG rating *5 stars\n").should.be.empty
    end

    it "does not read a multiplication as a repeat" do
      lint.("SET a 3*14\n").should.be.empty
    end

    it "says nothing about comments" do
      lint.("# REM Mon *14 MSG hi\n").should.be.empty
    end
  end

  it "reports at warning severity" do
    lint.("REM Mon *14 MSG hi\n").first.severity.should == "warning"
  end
end
