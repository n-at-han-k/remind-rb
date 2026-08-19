# frozen_string_literal: true

require_relative "../rule"
require_relative "../date_literal"

module RemLint
  module Rules
    # Clauses given a partial date where a full one is required.
    #
    # `FROM`, `UNTIL`, `THROUGH` and `COMPLETE-THROUGH` all read their argument
    # with `GetFullDate`, which insists on a year, a month and a day. A partial
    # date is `E_PARSE_ERR`.
    #
    # `COMPLETE-THROUGH` is the one that costs most. It is the starting point
    # of a TODO's whole trigger calculation, so a partial date does not merely
    # fail -- when the clause is missing or unusable the algorithm starts at
    # 1990-01-01 and the TODO is overdue by decades on its first run.
    #
    # Only reported when the argument is written out. A computed `[expr]` may
    # yield a perfectly good DATE and is not this rule's business.
    #
    # `OMIT` is excluded entirely. `OMIT ... THROUGH ...` is the omit-range
    # syntax rather than a reminder's expiry, and it takes partial dates on
    # purpose: Remind's own `tests/test.rem` writes `OMIT Jun THROUGH July 15`
    # and `OMIT Apr 2022 through July`.
    class ClauseNeedsFullDate < Rule
      CLAUSES = %w[FROM UNTIL THROUGH COMPLETE-THROUGH].freeze

      def self.default_severity
        "error"
      end

      def self.description
        "FROM, UNTIL, THROUGH or COMPLETE-THROUGH given a date that is not fully specified."
      end

      def check
        document.code_commands.each do |command|
          unless command.keyword?("OMIT")
            check_command(command)
          end
        end
      end

      private

        def check_command(command)
          trigger = document.trigger_for(command)

          CLAUSES.each do |name|
            check_clause(command, trigger.find(name))
          end
        end

        def check_clause(command, clause)
          if clause && !computed?(command, clause) && missing(command, clause)
            offend_at(command.logical_line, clause.offset, message(clause, command))
          end
        end

        # A bracketed expression right after the keyword supplies the date at
        # run time.
        def computed?(command, clause)
          tokens = document.tokens_for(command.logical_line)

          tokens[clause.argument_index]&.type == :lbracket
        end

        # The components `GetFullDate` did not get.
        def missing(command, clause)
          tokens = document.tokens_for(command.logical_line)
          date = DateLiteral.at(tokens, clause.argument_index)

          date.nil?
        end

        def message(clause, command)
          "`#{clause.name}` needs a full date -- a year, a month and a day -- " \
          "and #{written(command, clause)} is not one"
        end

        def written(command, clause)
          rest = command.text[clause.end_offset..].to_s
          words = rest.strip.split(/\s+/).first(3).join(" ")

          "`#{words}`"
        end
    end
  end
end

__END__

require_relative "../document"

describe "RemLint::Rules::ClauseNeedsFullDate" do
  lint = proc do |text|
    source = RemLint::Source.new(path: "t.rem", text: text)

    RemLint::Rules::ClauseNeedsFullDate.new.run(RemLint::Document.new(source))
  end

  messages = proc { |text| lint.(text).map(&:message) }

  describe "dates that are complete" do
    it "accepts the ISO form" do
      lint.("REM Mon UNTIL 2027-01-01 MSG hi\n").should.be.empty
    end

    it "accepts the spelled-out form" do
      lint.("REM Mon UNTIL 1 Jan 2027 MSG hi\n").should.be.empty
      lint.("REM Mon FROM Jan 1 2027 MSG hi\n").should.be.empty
    end

    it "accepts COMPLETE-THROUGH with a full date" do
      lint.("REM Mon COMPLETE-THROUGH 2027-01-01 TODO MSG hi\n").should.be.empty
    end
  end

  describe "dates that are partial" do
    it "reports a missing year" do
      messages.("REM Mon UNTIL 1 Jan MSG hi\n").first.should ==
        "`UNTIL` needs a full date -- a year, a month and a day -- and `1 Jan MSG` is not one"
    end

    it "reports a missing day" do
      messages.("REM Mon FROM Jan 2027 MSG hi\n").length.should == 1
    end

    it "reports a bare year" do
      messages.("REM Mon UNTIL 2027 MSG hi\n").length.should == 1
    end

    it "reports each clause that is short" do
      messages.("REM Mon FROM 1 Jan UNTIL 2 Feb MSG hi\n").length.should == 2
    end

    it "reports THROUGH" do
      messages.("REM Mon THROUGH 1 Jan MSG hi\n").first.should.match(/`THROUGH` needs a full date/)
    end

    it "points at the clause" do
      text = "REM Mon UNTIL 1 Jan MSG hi\n"

      lint.(text).first.column.should == text.index("UNTIL") + 1
    end
  end

  describe "arguments it cannot judge" do
    it "says nothing about a computed date" do
      lint.("REM Mon UNTIL [expiry()] MSG hi\n").should.be.empty
    end
  end

  it "says nothing about a reminder with none of these clauses" do
    lint.("REM Mon MSG hi\n").should.be.empty
  end

  it "says nothing about SCANFROM, which also takes a delta" do
    lint.("REM Mon SCANFROM -7 MSG hi\n").should.be.empty
  end

  it "says nothing about THROUGH inside an OMIT, which takes partial dates" do
    # Both forms are in Remind's own tests/test.rem and both work.
    lint.("OMIT Jun THROUGH July 15\n").should.be.empty
    lint.("OMIT Apr 2022 through July\n").should.be.empty
  end

  it "says nothing about comments" do
    lint.("# REM Mon UNTIL 1 Jan MSG hi\n").should.be.empty
  end

  it "reports at error severity" do
    lint.("REM Mon UNTIL 1 Jan MSG hi\n").first.severity.should == "error"
  end
end
