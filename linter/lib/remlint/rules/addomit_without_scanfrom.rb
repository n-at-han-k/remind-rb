# frozen_string_literal: true

require_relative "../rule"

module RemLint
  module Rules
    # `ADDOMIT` with no `SCANFROM`, which adds the wrong year's holiday.
    #
    # `ADDOMIT` puts a movable holiday's computed date into the omit context.
    # But Remind computes a reminder's trigger by scanning forward from today,
    # so the day *after* the holiday the trigger has already moved to next
    # year's occurrence -- and it is next year's date that gets added.
    # Reminders that `SKIP`, `BEFORE` or `AFTER` around the holiday then work
    # perfectly until the day after it, and are quietly wrong from then on.
    #
    # `SCANFROM` fixes it by making the scan start far enough back that the
    # current year's date stays the trigger. Remind warns about a missing one
    # itself, and names the same figure:
    #
    #   Warning: Consider using SCANFROM -28 with recurring ADDOMIT
    #
    # This rule says it before the file is ever run, and keeps to Remind's
    # scope: a trigger built from a bracketed expression is opaque to both of
    # us, so neither reports it. `include/holidays/cl.rem` has one
    # (`REM [datepart(soleq(1, $U-28))] ADDOMIT ...`) and Remind is quiet
    # about it, so this is too.
    #
    # The *width* of the window is a judgement rather than a fact, and so is
    # off by default. Chapter 4 works through 28 days, and
    # `include/holidays/us.rem` uses exactly that -- but `examples/defs.rem`
    # uses `SCANFROM -7` twenty-seven times, and that is not a bug: it is a
    # smaller guarantee, adequate for holidays whose dependent reminders are
    # all within a week. Set `MinimumWindow` to 28 to ask for the wider one.
    class AddomitWithoutScanfrom < Rule
      # The figure chapter 4 works through, used only in the message and as
      # the suggestion for a missing SCANFROM.
      RECOMMENDED = 28

      def self.default_severity
        "warning"
      end

      def self.description
        "ADDOMIT with no SCANFROM, which adds next year's date the day after the holiday."
      end

      def check
        document.code_commands.each do |command|
          trigger = document.trigger_for(command)

          if trigger.include?("ADDOMIT") && !computed?(command, trigger)
            check_scanfrom(command, trigger)
          end
        end
      end

      private

        # A trigger whose date comes out of an expression. Remind's own
        # warning does not fire on these and neither does this rule.
        def computed?(command, trigger)
          limit = trigger.body_offset || command.text.length

          document.tokens_for(command.logical_line).any? do |token|
            token.type == :lbracket && token.offset < limit
          end
        end

        def check_scanfrom(command, trigger)
          scanfrom = trigger.find("SCANFROM")

          if scanfrom.nil?
            offend_at(command.logical_line, trigger.find("ADDOMIT").offset, missing_message)
          else
            check_window(command, scanfrom)
          end
        end

        # Zero -- the default -- means "any window will do", which is the
        # honest position: a narrower one is a smaller guarantee, not a fault.
        def check_window(command, scanfrom)
          minimum = option("MinimumWindow", 0)
          days = window(command, scanfrom)

          if minimum.positive? && days && days < minimum
            offend_at(command.logical_line, scanfrom.offset, narrow_message(days, minimum))
          end
        end

        # `SCANFROM -28` -- the delta form, which is the one that matters here.
        def window(command, scanfrom)
          text = command.text[scanfrom.end_offset..].to_s.strip[/\A-\d+/]

          text&.delete("-")&.to_i
        end

        def missing_message
          "`ADDOMIT` with no `SCANFROM` adds *next* year's date once the day itself has " \
          "passed, so anything skipping around this holiday is wrong from the day after " \
          "it; `SCANFROM -#{RECOMMENDED}` keeps the addition stable"
        end

        def narrow_message(days, minimum)
          "`SCANFROM -#{days}` is narrower than the #{minimum} days this project asks " \
          "for, so a reminder more than #{days} days from the holiday can still see the " \
          "wrong year's date"
        end
    end
  end
end

__END__

require_relative "../document"

describe "RemLint::Rules::AddomitWithoutScanfrom" do
  lint = proc do |text, config = {}|
    source = RemLint::Source.new(path: "t.rem", text: text)

    RemLint::Rules::AddomitWithoutScanfrom.new(config).run(RemLint::Document.new(source))
  end

  messages = proc { |text, config = {}| lint.(text, config).map(&:message) }

  wide = { "MinimumWindow" => 28 }

  it "reports ADDOMIT with no SCANFROM" do
    messages.("REM Mon 1 Apr ADDOMIT MSG Holiday\n").first.should.match(
      /adds \*next\* year's date once the day itself has passed/,
    )
  end

  it "suggests the window" do
    messages.("REM Mon 1 Apr ADDOMIT MSG Holiday\n").first.should.match(/`SCANFROM -28`/)
  end

  it "accepts ADDOMIT with a wide enough SCANFROM" do
    lint.("REM Thu Nov 22 SCANFROM -28 ADDOMIT MSG Thanksgiving\n").should.be.empty
  end

  it "accepts a wider window still" do
    lint.("REM Thu Nov 22 SCANFROM -60 ADDOMIT MSG Thanksgiving\n").should.be.empty
  end

  it "accepts any window by default" do
    # examples/defs.rem writes SCANFROM -7 twenty-seven times, and that is a
    # smaller guarantee rather than a mistake.
    lint.("REM Thu Nov 22 SCANFROM -7 ADDOMIT MSG Thanksgiving\n").should.be.empty
  end

  it "reports a narrow window when the project asks for a wider one" do
    messages.("REM Thu Nov 22 SCANFROM -7 ADDOMIT MSG x\n", wide).first.should.match(
      /`SCANFROM -7` is narrower than the 28 days this project asks for/,
    )
  end

  it "accepts exactly the configured minimum" do
    lint.("REM Thu Nov 22 SCANFROM -28 ADDOMIT MSG x\n", wide).should.be.empty
  end

  it "says nothing about a reminder with no ADDOMIT" do
    lint.("REM Thu Nov 22 SCANFROM -7 MSG Thanksgiving\n").should.be.empty
  end

  it "says nothing when SCANFROM takes a date rather than a delta" do
    # A fixed scan date is a different thing and not this rule's to judge.
    lint.("REM Thu Nov 22 SCANFROM 2026-01-01 ADDOMIT MSG x\n", wide).should.be.empty
  end

  it "points at the ADDOMIT when there is no SCANFROM" do
    text = "REM Mon 1 Apr ADDOMIT MSG Holiday\n"

    lint.(text).first.column.should == text.index("ADDOMIT") + 1
  end

  it "says nothing about a trigger built from an expression" do
    # include/holidays/cl.rem has one of these and Remind does not warn about
    # it either -- the trigger is opaque to both of us.
    lint.("REM [datepart(soleq(1, $U-28))] ADDOMIT MSG Solstice\n").should.be.empty
  end

  it "says nothing about comments" do
    lint.("# REM Mon 1 Apr ADDOMIT MSG Holiday\n").should.be.empty
  end

  it "reports at warning severity" do
    lint.("REM Mon 1 Apr ADDOMIT MSG x\n").first.severity.should == "warning"
  end
end
