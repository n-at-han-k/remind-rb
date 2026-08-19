# frozen_string_literal: true

require_relative "../rule"

module RemLint
  module Rules
    # `INFO` clauses a back-end will drop.
    #
    # `INFO` attaches a `"Header: value"` pair to a reminder, which the
    # machine-readable back-ends carry through and `%<Header>` reads back. Two
    # things go wrong, and a back-end's only recourse for either is to ignore
    # the clause:
    #
    #   INFO with no quoted "Header: value" string
    #   two INFO clauses on one command with the same header
    #
    # Headers are not case-sensitive, so `Url:` and `URL:` on one command are
    # the same collision -- which is exactly the sort of duplicate that reads
    # as two distinct pieces of information.
    #
    # The reminder still triggers either way. What goes missing is the location
    # or the URL, silently, in the calendar app at the far end of the export.
    class InfoClause < Rule
      # `"Header: value"` -- the header runs to the first colon and cannot
      # contain a quote.
      WELL_FORMED = /\A(?<quote>["'])(?<header>[^:"']+):(?<value>.*)\k<quote>\z/m

      def self.default_severity
        "warning"
      end

      def self.description
        "An INFO clause that is malformed, or duplicates another's header."
      end

      def check
        document.code_commands.each do |command|
          check_command(command)
        end
      end

      private

        def check_command(command)
          seen = {}

          document.trigger_for(command).clauses.each do |clause|
            if clause.name == "INFO"
              check_clause(command, clause, seen)
            end
          end
        end

        def check_clause(command, clause, seen)
          argument = argument_of(command, clause)
          match = argument&.match(WELL_FORMED)

          if match.nil?
            report_malformed(command, clause, argument)
          else
            check_duplicate(
              command,
              clause,
              match[:header].strip,
              seen,
            )
          end
        end

        # The whole quoted string after the keyword, if there is one.
        def argument_of(command, clause)
          tokens = document.tokens_for(command.logical_line)
          token = tokens[clause.argument_index]

          if token&.type == :string
            token.value
          end
        end

        def report_malformed(command, clause, argument)
          offend_at(
            command.logical_line,
            clause.offset,
            "`INFO` takes a quoted \"Header: value\" string; " \
            "#{argument ? "`#{argument}`" : 'this'} is not one",
          )
        end

        def check_duplicate(command, clause, header, seen)
          key = header.downcase
          first = seen[key]

          if first
            offend_at(
              command.logical_line,
              clause.offset,
              "`#{header}:` repeats the header given on this command as `#{first}:`; " \
              "headers are not case-sensitive and cannot be duplicated",
            )
          else
            seen[key] = header
          end
        end
    end
  end
end

__END__

require_relative "../document"

describe "RemLint::Rules::InfoClause" do
  lint = proc do |text|
    source = RemLint::Source.new(path: "t.rem", text: text)

    RemLint::Rules::InfoClause.new.run(RemLint::Document.new(source))
  end

  messages = proc { |text| lint.(text).map(&:message) }

  describe "clauses that are fine" do
    it "accepts a well-formed INFO" do
      lint.(%(REM 1 Jan INFO "Location: The pub" MSG Meet up\n)).should.be.empty
    end

    it "accepts two INFO clauses with different headers" do
      lint.(%(REM 1 Jan INFO "Location: pub" INFO "Url: x" MSG hi\n)).should.be.empty
    end

    it "accepts a value containing a colon" do
      lint.(%(REM 1 Jan INFO "Url: https://example.com/x" MSG hi\n)).should.be.empty
    end

    it "accepts a reminder with no INFO at all" do
      lint.("REM 1 Jan MSG hi\n").should.be.empty
    end
  end

  describe "malformed clauses" do
    it "reports an unquoted argument" do
      messages.("REM 1 Jan INFO Location: pub MSG hi\n").first.should.match(
        /takes a quoted "Header: value" string/,
      )
    end

    it "reports a quoted string with no colon" do
      messages.(%(REM 1 Jan INFO "Location" MSG hi\n)).length.should == 1
    end

    it "quotes what was written back" do
      messages.(%(REM 1 Jan INFO "Location" MSG hi\n)).first.should.match(/`"Location"` is not one/)
    end
  end

  describe "duplicate headers" do
    it "reports the same header twice" do
      messages.(%(REM 1 Jan INFO "Url: a" INFO "Url: b" MSG hi\n)).first.should ==
        "`Url:` repeats the header given on this command as `Url:`; " \
        "headers are not case-sensitive and cannot be duplicated"
    end

    it "reports a header that differs only in case" do
      messages.(%(REM 1 Jan INFO "Url: a" INFO "URL: b" MSG hi\n)).first.should.match(
        /`URL:` repeats the header given on this command as `Url:`/,
      )
    end

    it "reports only the second of two" do
      lint.(%(REM 1 Jan INFO "Url: a" INFO "Url: b" MSG hi\n)).length.should == 1
    end

    it "does not carry headers between commands" do
      text = %(REM 1 Jan INFO "Url: a" MSG hi\nREM 2 Jan INFO "Url: b" MSG hi\n)

      lint.(text).should.be.empty
    end
  end

  it "says nothing about comments" do
    lint.(%(# REM 1 Jan INFO "Url: a" INFO "Url: b" MSG hi\n)).should.be.empty
  end

  it "reports at warning severity" do
    lint.(%(REM 1 Jan INFO "Location" MSG hi\n)).first.severity.should == "warning"
  end
end
