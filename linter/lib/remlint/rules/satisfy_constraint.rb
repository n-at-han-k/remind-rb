# frozen_string_literal: true

require_relative "../rule"

module RemLint
  module Rules
    # `SATISFY` expressions that belong in the trigger.
    #
    # `SATISFY` works by trial: Remind proposes a date, evaluates the
    # expression, and moves on a day if it comes back false. Anything the
    # trigger could have pinned down instead is therefore paid for once per
    # candidate date rather than once.
    #
    # Chapter 7 measures it. Over 100,000 runs the all-SATISFY form evaluates
    # the expression 13,214,377 times and takes 2.30s; moving the day into the
    # trigger drops that to 482,026 evaluations and 0.58s. Same reminder, four
    # times the speed, and the edit is mechanical:
    #
    #   REM SATISFY [$Td == 13 && $Tw == 5]     ->  REM 13 SATISFY [$Tw == 5]
    #
    # Three trigger components can be hoisted, and each is reported only when
    # it is compared with `==` against a literal, which is the form that
    # translates directly into the trigger:
    #
    #   $Td  the day of the month
    #   $Tm  the month
    #   $Ty  the year
    #
    # Two further faults share the same walk. A constraint no date can satisfy
    # -- `$Td == 100` -- costs `$MaxSatIter` iterations and then prints
    # `Can't compute trigger`. And a `$Ty <` term is an `UNTIL` written the
    # expensive way, which the book calls bad practice for the same reason.
    class SatisfyConstraint < Rule
      # The trigger components a trigger can express directly, and the clause
      # each becomes.
      HOISTABLE = {
        "Td" => "a day",
        "Tm" => "a month",
        "Ty" => "a year",
      }.freeze

      RANGES = {
        "Td" => (1..31),
        "Tm" => (1..12),
        "Ty" => (1990..5990),
      }.freeze

      # `$Td == 13` and `$Ty < 2029`, as they arrive from the lexer.
      COMPARISON = /\$(?<name>T[dmy])\s*(?<operator><=|>=|==|!=|<|>)\s*(?<value>\d+)/

      def self.enabled_by_default?
        false
      end

      def self.default_severity
        "info"
      end

      def self.description
        "A SATISFY constraint the trigger could express, or that no date satisfies."
      end

      def check
        document.code_commands.each do |command|
          trigger = document.trigger_for(command)

          if trigger.body&.name == "SATISFY"
            check_satisfy(command, trigger)
          end
        end
      end

      private

        def check_satisfy(command, trigger)
          body = command.text[trigger.body_offset..].to_s
          already = pinned(command, trigger)

          body.to_enum(:scan, COMPARISON).each do
            match = Regexp.last_match

            report(
              command,
              trigger,
              match,
              already,
            )
          end
        end

        # A component the trigger already names is not one to hoist.
        def pinned(command, trigger)
          tokens = document.tokens_for(command.logical_line)
          limit = trigger.body.offset

          tokens.select { |token| token.offset < limit }.map(&:type)
        end

        def report(command, trigger, match, already)
          name = match[:name]
          value = match[:value].to_i
          offset = trigger.body_offset + match.begin(0)

          if !RANGES.fetch(name).cover?(value)
            offend_at(command.logical_line, offset, unsatisfiable(name, match))
          elsif match[:operator] == "==" && !already.include?(:number)
            offend_at(command.logical_line, offset, hoistable(name, match))
          elsif name == "Ty" && ["<", "<="].include?(match[:operator])
            offend_at(command.logical_line, offset, bounded(match))
          end
        end

        def unsatisfiable(name, match)
          "`$#{name} #{match[:operator]} #{match[:value]}` can never hold -- " \
          "#{name} runs #{RANGES.fetch(name).first} to #{RANGES.fetch(name).last} -- so " \
          "this costs $MaxSatIter iterations and then prints `Can't compute trigger`"
        end

        def hoistable(name, match)
          "`$#{name} == #{match[:value]}` is #{HOISTABLE.fetch(name)} the trigger could " \
          "name directly; hoisting it stops the expression being evaluated once per " \
          "candidate date"
        end

        def bounded(match)
          "`$Ty #{match[:operator]} #{match[:value]}` is an `UNTIL` written as a " \
          "constraint; `UNTIL #{match[:value].to_i - 1}-12-31` says the same thing " \
          "without a search"
        end
    end
  end
end

__END__

require_relative "../document"

describe "RemLint::Rules::SatisfyConstraint" do
  lint = proc do |text|
    source = RemLint::Source.new(path: "t.rem", text: text)

    RemLint::Rules::SatisfyConstraint.new.run(RemLint::Document.new(source))
  end

  messages = proc { |text| lint.(text).map(&:message) }

  it "is off unless the configuration asks for it" do
    RemLint::Rules::SatisfyConstraint.enabled_by_default?.should.be.false
  end

  describe "constraints the trigger could express" do
    it "reports a day" do
      messages.("REM SATISFY [$Td == 13]\n").first.should.match(
        /is a day the trigger could name directly/,
      )
    end

    it "reports a month and a year" do
      messages.("REM SATISFY [$Tm == 6]\n").first.should.match(/is a month the trigger could/)
      messages.("REM SATISFY [$Ty == 2027]\n").first.should.match(/is a year the trigger could/)
    end

    it "explains the cost" do
      messages.("REM SATISFY [$Td == 13]\n").first.should.match(
        /once per candidate date/,
      )
    end

    it "accepts a constraint the trigger already pins down" do
      # `REM 13 SATISFY [$Tw == 5]` is the fixed form from chapter 7.
      lint.("REM 13 SATISFY [$Tw == 5]\n").should.be.empty
    end

    it "says nothing about a weekday, which a trigger cannot pin this way" do
      lint.("REM SATISFY [$Tw == 5]\n").should.be.empty
    end
  end

  describe "constraints no date satisfies" do
    it "reports a day out of range" do
      messages.("REM SATISFY [$Td == 100]\n").first.should.match(
        /can never hold -- Td runs 1 to 31/,
      )
    end

    it "names the cost" do
      messages.("REM SATISFY [$Td == 100]\n").first.should.match(
        /costs \$MaxSatIter iterations and then prints `Can't compute trigger`/,
      )
    end

    it "reports a month out of range" do
      messages.("REM SATISFY [$Tm == 13]\n").first.should.match(/Tm runs 1 to 12/)
    end

    it "reports a year out of range" do
      messages.("REM SATISFY [$Ty == 1970]\n").first.should.match(/Ty runs 1990 to 5990/)
    end
  end

  describe "a year bound written as a constraint" do
    it "is reported as an UNTIL" do
      messages.("REM 13 SATISFY [$Ty < 2029]\n").first.should ==
        "`$Ty < 2029` is an `UNTIL` written as a constraint; `UNTIL 2028-12-31` says " \
        "the same thing without a search"
    end

    it "is reported for <= too" do
      messages.("REM 13 SATISFY [$Ty <= 2029]\n").length.should == 1
    end
  end

  it "says nothing about a REM with no SATISFY" do
    lint.("REM 13 MSG hi\n").should.be.empty
  end

  it "says nothing about comments" do
    lint.("# REM SATISFY [$Td == 13]\n").should.be.empty
  end

  it "points at the constraint" do
    text = "REM SATISFY [$Td == 13]\n"

    lint.(text).first.column.should == text.index("$Td") + 1
  end

  it "reports at info severity" do
    lint.("REM SATISFY [$Td == 13]\n").first.severity.should == "info"
  end
end
