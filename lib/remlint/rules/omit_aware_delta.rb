# frozen_string_literal: true

require_relative "../rule"

module RemLint
  module Rules
    # A single-sign delta in a file with nothing omitted.
    #
    # `++n` counts calendar days back from the event; `+n` counts *non-omitted*
    # days. The distinction is the whole point of the single-sign form, and it
    # is exactly nothing when the omit context is empty: with no `OMIT`
    # anywhere, `+n` and `++n` produce identical reminders.
    #
    # So a single sign in a file with no omits is one of two things, and both
    # are worth a look: a `+` that was meant to be `++`, or a reminder that
    # depends on an `OMIT` somebody forgot to write. The same holds for the
    # single-tilde back, `~n`.
    #
    # Off by default. A file that gets its omits from an `INCLUDE` is correct
    # and this rule cannot see that -- which is why the check also stays quiet
    # in any file that includes anything.
    class OmitAwareDelta < Rule
      # `+3` and `~3`, but not `++3` or `~~3`, and not an arithmetic `+`.
      SINGLE = /(?<![+~\d\w])(?<sign>[+~])(?![+~])(?<count>\d+)(?!\S)/

      # `OMIT` is a command; `ADDOMIT` and `OMITFUNC` are clauses on a `REM`,
      # so both places have to be looked at.
      OMIT_COMMANDS = %w[OMIT].freeze

      OMIT_CLAUSES = %w[ADDOMIT OMITFUNC].freeze

      INCLUDE_COMMANDS = %w[INCLUDE SYSINCLUDE INCLUDECMD DO].freeze

      def self.enabled_by_default?
        false
      end

      def self.default_severity
        "info"
      end

      def self.description
        "A single-sign delta or back in a file that omits nothing."
      end

      def check
        if omits? || includes?
          nil
        else
          report_deltas
        end
      end

      private

        def omits?
          document.code_commands.any? do |command|
            command.keyword?(*OMIT_COMMANDS) ||
              document.trigger_for(command).include?(*OMIT_CLAUSES)
          end
        end

        # A file that includes something may be getting its omits from there.
        def includes?
          document.code_commands.any? { |command| command.keyword?(*INCLUDE_COMMANDS) }
        end

        def report_deltas
          document.code_commands.each do |command|
            trigger = document.trigger_for(command)

            if trigger.triggered?
              scan(command, trigger)
            end
          end
        end

        def scan(command, trigger)
          limit = trigger.body_offset || command.text.length
          head = command.text[0...limit].to_s

          head.to_enum(:scan, SINGLE).each do
            match = Regexp.last_match

            offend_at(command.logical_line, match.begin(0), message(match))
          end
        end

        def message(match)
          sign = match[:sign]
          doubled = sign * 2

          "`#{sign}#{match[:count]}` counts non-omitted days, and this file omits " \
          "nothing -- so it is exactly `#{doubled}#{match[:count]}`; either the sign " \
          "was meant to be doubled or an `OMIT` is missing"
        end
    end
  end
end

__END__

require_relative "../document"

describe "RemLint::Rules::OmitAwareDelta" do
  lint = proc do |text|
    source = RemLint::Source.new(path: "t.rem", text: text)

    RemLint::Rules::OmitAwareDelta.new.run(RemLint::Document.new(source))
  end

  messages = proc { |text| lint.(text).map(&:message) }

  it "is off unless the configuration asks for it" do
    RemLint::Rules::OmitAwareDelta.enabled_by_default?.should.be.false
  end

  it "reports a single-plus delta in a file with no omits" do
    messages.("REM 16 July +10 MSG hi\n").first.should.match(
      /counts non-omitted days, and this file omits nothing/,
    )
  end

  it "suggests the doubled sign" do
    messages.("REM 16 July +10 MSG hi\n").first.should.match(/exactly `\+\+10`/)
  end

  it "reports a single tilde back" do
    messages.("REM 16 July ~3 MSG hi\n").first.should.match(/exactly `~~3`/)
  end

  it "accepts a doubled delta" do
    lint.("REM 16 July ++10 MSG hi\n").should.be.empty
  end

  it "accepts a doubled back" do
    lint.("REM 16 July ~~3 MSG hi\n").should.be.empty
  end

  it "says nothing in a file that omits something" do
    lint.("OMIT 1 Jan\nREM 16 July +10 MSG hi\n").should.be.empty
  end

  it "says nothing in a file that uses ADDOMIT" do
    lint.("REM 1 Apr ADDOMIT MSG x\nREM 16 July +10 MSG hi\n").should.be.empty
  end

  it "says nothing in a file that includes anything" do
    # The omits may be in the included file.
    lint.("INCLUDE defs.rem\nREM 16 July +10 MSG hi\n").should.be.empty
  end

  it "does not read a delta out of the body" do
    lint.("REM 16 July MSG the score was +10\n").should.be.empty
  end

  it "does not read arithmetic as a delta" do
    lint.("SET a 3 +10\n").should.be.empty
  end

  it "says nothing about comments" do
    lint.("# REM 16 July +10 MSG hi\n").should.be.empty
  end

  it "reports at info severity" do
    lint.("REM 16 July +10 MSG hi\n").first.severity.should == "info"
  end
end
