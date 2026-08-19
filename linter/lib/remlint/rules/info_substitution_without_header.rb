# frozen_string_literal: true

require_relative "../rule"

module RemLint
  module Rules
    # `%<Header>` with no matching `INFO` on the same command.
    #
    # `FindTrigInfo` returns NULL and `dosubst.c` ships nothing at all, so the
    # substitution expands to the empty string. The reminder then reads
    # `Meeting at ` and looks like a truncation bug somewhere else entirely.
    #
    # `INFO` headers are per-command, so this is decidable from one line: the
    # headers a command carries and the headers its body asks for are both
    # right there. Matching is case-insensitive, because Remind's header
    # lookup is.
    class InfoSubstitutionWithoutHeader < Rule
      # `INFO "Header: value"` -- the argument is a quoted string whose header
      # runs up to the first colon.
      INFO_HEADER = /\A["'](?<header>[^:"']+):/

      REFERENCE = /%<(?<header>[^>]*)>/

      def self.default_severity
        "warning"
      end

      def self.description
        "A %<Header> substitution with no INFO clause of that name on the command."
      end

      def check
        document.code_commands.each do |command|
          check_command(command)
        end
      end

      private

        def check_command(command)
          trigger = document.trigger_for(command)

          if trigger.text_body?
            report(command, headers(command, trigger))
          end
        end

        # The headers this command declares, downcased for comparison.
        def headers(command, trigger)
          trigger.clauses.filter_map do |clause|
            if clause.name == "INFO"
              header_of(command, clause)
            end
          end
        end

        # The header name in the string that follows the INFO keyword.
        def header_of(command, clause)
          rest = command.text[clause.end_offset..].to_s
          match = rest.sub(/\A\s+/, "").match(INFO_HEADER)

          match && match[:header].strip.downcase
        end

        def report(command, declared)
          trigger = document.trigger_for(command)
          body = command.text[trigger.body_offset..].to_s

          body.to_enum(:scan, REFERENCE).each do
            match = Regexp.last_match

            unless declared.include?(match[:header].strip.downcase)
              offend_at(command.logical_line, trigger.body_offset + match.begin(0), message(match))
            end
          end
        end

        def message(match)
          "`%<#{match[:header]}>` has no matching `INFO` clause on this command; " \
          "it expands to nothing"
        end
    end
  end
end

__END__

require_relative "../document"

describe "RemLint::Rules::InfoSubstitutionWithoutHeader" do
  lint = proc do |text|
    source = RemLint::Source.new(path: "t.rem", text: text)

    RemLint::Rules::InfoSubstitutionWithoutHeader.new.run(RemLint::Document.new(source))
  end

  messages = proc { |text| lint.(text).map(&:message) }

  describe "references that match" do
    it "accepts a header the command declares" do
      lint.(%(REM 1 Jan INFO "Location: The pub" MSG Meet at %<Location>\n)).should.be.empty
    end

    it "matches case-insensitively, as Remind's lookup does" do
      lint.(%(REM 1 Jan INFO "Location: pub" MSG Meet at %<LOCATION>\n)).should.be.empty
      lint.(%(REM 1 Jan INFO "URL: x" MSG See %<Url>\n)).should.be.empty
    end

    it "accepts several headers on one command" do
      text = %(REM 1 Jan INFO "Location: pub" INFO "Url: x" MSG %<Location> %<Url>\n)

      lint.(text).should.be.empty
    end

    it "accepts a header declared after the reference is written" do
      # Clause order does not matter; both are on the same command.
      lint.(%(REM 1 Jan INFO "Location: pub" MSG at %<Location>\n)).should.be.empty
    end
  end

  describe "references that do not match" do
    it "reports a header the command never declares" do
      messages.("REM 1 Jan MSG Meet at %<Location>\n").first.should ==
        "`%<Location>` has no matching `INFO` clause on this command; it expands to nothing"
    end

    it "reports a misspelled header" do
      messages.(%(REM 1 Jan INFO "Location: pub" MSG at %<Locaton>\n)).length.should == 1
    end

    it "reports each unmatched reference" do
      messages.("REM 1 Jan MSG %<A> and %<B>\n").length.should == 2
    end

    it "does not confuse headers between two commands" do
      text = %(REM 1 Jan INFO "Location: pub" MSG at %<Location>\nREM 2 Jan MSG at %<Location>\n)

      lint.(text).map(&:line).should == [2]
    end

    it "points at the reference" do
      text = "REM 1 Jan MSG Meet at %<Location>\n"

      lint.(text).first.column.should == text.index("%<") + 1
    end
  end

  describe "what it leaves alone" do
    it "says nothing about a body with no reference" do
      lint.(%(REM 1 Jan INFO "Location: pub" MSG Meet up\n)).should.be.empty
    end

    it "says nothing about a command with no body" do
      lint.("SET a 1\n").should.be.empty
    end

    it "says nothing about comments" do
      lint.("# uses %<Location> somewhere\n").should.be.empty
    end
  end

  it "reports at warning severity" do
    lint.("REM 1 Jan MSG %<Location>\n").first.severity.should == "warning"
  end

  it "reports the physical line inside a continuation" do
    lint.("REM 1 Jan MSG a \\\n    %<Location>\n").first.line.should == 2
  end
end
