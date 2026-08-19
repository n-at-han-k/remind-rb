# frozen_string_literal: true

require_relative "../rule"
require_relative "../date_literal"

module RemLint
  module Rules
    # A reminder whose window closes before it opens.
    #
    # `FROM` and `SCANFROM` set the date Remind starts scanning from; `UNTIL`
    # (and its synonym `THROUGH`) sets the date the reminder expires. An
    # `UNTIL` strictly before the start describes an empty window, and the
    # reminder can never fire.
    #
    # Unusually for this linter, Remind is not silent here: it warns at parse
    # time, with a different message for each start keyword --
    #
    #   Warning: UNTIL/THROUGH date earlier than FROM date
    #   Warning: UNTIL/THROUGH date earlier than SCANFROM date
    #
    # -- so the value on offer is smaller than usual: saying it in the editor
    # and in CI rather than only when someone runs the file and reads stderr.
    # Remind's own `tests/test.rem` marks both forms "Diagnosed".
    #
    # Strictly before, not on or before. `FROM 1992-01-06 UNTIL 1992-01-06` is
    # a legal one-day window and fires on the day; Remind's own warning says
    # "earlier than" for the same reason.
    #
    # Both dates have to be fully spelled out for this to be decidable, which
    # is no restriction: `GetFullDate` requires exactly that of both keywords.
    class UntilBeforeFrom < Rule
      # `UNTIL` and `THROUGH` are the same clause -- `ParseUntil` takes both
      # and writes the same field.
      EXPIRY = %w[UNTIL THROUGH].freeze

      # `FROM` and `SCANFROM` are different clauses that both set where the
      # scan begins, and Remind checks the expiry against either.
      START = %w[FROM SCANFROM].freeze

      def self.default_severity
        "error"
      end

      def self.description
        "An UNTIL or THROUGH date earlier than the reminder's FROM or SCANFROM."
      end

      def check
        document.code_commands.each do |command|
          check_window(command)
        end
      end

      private

        def check_window(command)
          trigger = document.trigger_for(command)
          start = first_clause(trigger, START)
          expiry = first_clause(trigger, EXPIRY)
          from = clause_date(command, start)
          until_date = clause_date(command, expiry)

          if from && until_date && until_date < from
            report(
              command,
              start,
              expiry,
              from,
              until_date,
            )
          end
        end

        def first_clause(trigger, names)
          names.filter_map { |name| trigger.find(name) }.first
        end

        # The date written immediately after a clause keyword.
        def clause_date(command, clause)
          if clause
            tokens = document.tokens_for(command.logical_line)

            DateLiteral.at(tokens, clause.argument_index)
          end
        end

        def report(command, start, expiry, from, until_date)
          offend_at(
            command.logical_line,
            expiry.offset,
            "`#{expiry.name} #{until_date}` is earlier than " \
            "`#{start.name} #{from}`, so this reminder can never trigger",
          )
        end
    end
  end
end

__END__

require_relative "../document"

describe "RemLint::Rules::UntilBeforeFrom" do
  lint = proc do |text|
    source = RemLint::Source.new(path: "t.rem", text: text)

    RemLint::Rules::UntilBeforeFrom.new.run(RemLint::Document.new(source))
  end

  messages = proc { |text| lint.(text).map(&:message) }

  describe "windows that can never open" do
    it "reports an UNTIL before the FROM" do
      messages.("REM Mon FROM 2027-03-01 UNTIL 2027-01-01 MSG hi\n").first.should ==
        "`UNTIL 2027-01-01` is earlier than `FROM 2027-03-01`, so this reminder can never trigger"
    end

    it "reports an UNTIL earlier than a SCANFROM" do
      # Remind warns about this one separately, and tests/test.rem marks it
      # "Diagnosed" alongside the FROM form.
      messages.("REM Mon SCANFROM 1992-01-01 UNTIL 1991-12-31 MSG hi\n").first.should.match(
        /earlier than `SCANFROM 1992-01-01`/,
      )
    end

    it "reports THROUGH, which is the same clause" do
      messages.("REM Mon FROM 2027-03-01 THROUGH 2027-01-01 MSG hi\n").first.should.match(
        /`THROUGH 2027-01-01` is earlier than/,
      )
    end

    it "reads the spelled-out date form" do
      messages.("REM Mon FROM 1 March 2027 UNTIL 1 Jan 2027 MSG hi\n").length.should == 1
    end

    it "reads the two forms mixed" do
      messages.("REM Mon FROM 2027-03-01 UNTIL 1 Jan 2027 MSG hi\n").length.should == 1
    end

    it "points at the expiry clause" do
      text = "REM Mon FROM 2027-03-01 UNTIL 2027-01-01 MSG hi\n"

      lint.(text).first.column.should == text.index("UNTIL") + 1
    end
  end

  describe "windows that are fine" do
    it "accepts an UNTIL after the FROM" do
      lint.("REM Mon FROM 2027-01-01 UNTIL 2027-03-01 MSG hi\n").should.be.empty
    end

    it "accepts an UNTIL one day after the FROM" do
      lint.("REM Mon FROM 2027-01-01 UNTIL 2027-01-02 MSG hi\n").should.be.empty
    end

    it "accepts a one-day window, which is legal and fires" do
      # `REM MON FROM 1992-01-06 UNTIL 1992-01-06` triggers on 1992-01-06.
      lint.("REM Mon FROM 2027-03-01 UNTIL 2027-03-01 MSG hi\n").should.be.empty
    end

    it "accepts a reminder with only one of the two" do
      lint.("REM Mon FROM 2027-01-01 MSG hi\n").should.be.empty
      lint.("REM Mon UNTIL 2027-01-01 MSG hi\n").should.be.empty
    end

    it "accepts a reminder with neither" do
      lint.("REM Mon MSG hi\n").should.be.empty
    end

    it "says nothing about a SCANFROM written as a delta" do
      # `SCANFROM -7` has no date to compare against.
      lint.("REM Mon SCANFROM -7 UNTIL 2027-01-01 MSG hi\n").should.be.empty
    end

    it "does not read the two clauses across different commands" do
      text = "REM Mon FROM 2027-03-01 MSG a\nREM Tue UNTIL 2027-01-01 MSG b\n"

      lint.(text).should.be.empty
    end
  end

  describe "dates it cannot read" do
    it "says nothing when a date is computed" do
      lint.("REM Mon FROM [x] UNTIL 2027-01-01 MSG hi\n").should.be.empty
    end

    it "says nothing when a date is partial" do
      # GetFullDate would reject it; that is a different rule's offence.
      lint.("REM Mon FROM 1 Jan UNTIL 2027-01-01 MSG hi\n").should.be.empty
    end
  end

  it "says nothing about comments" do
    lint.("# FROM 2027-03-01 UNTIL 2027-01-01\n").should.be.empty
  end

  it "reports at error severity" do
    lint.("REM Mon FROM 2027-03-01 UNTIL 2027-01-01 MSG hi\n").first.severity.should == "error"
  end

  it "reports the physical line inside a continuation" do
    lint.("REM Mon FROM 2027-03-01 \\\n    UNTIL 2027-01-01 MSG hi\n").first.line.should == 2
  end
end
