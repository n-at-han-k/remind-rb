# frozen_string_literal: true

require_relative "../rule"

module RemLint
  module Rules
    # Things a file does that its declared invocation will not deliver.
    #
    # Three checks want the command line rather than the file, and a file that
    # declares one gets all three:
    #
    #     # remlint:invocation remind -pp -g /path/to/file
    #
    # SORT SPEC. `-g` takes up to four characters, each `a` or `d`. Anything
    # else is silently ignored, so a sort somebody asked for never happens.
    #
    # INFO HEADERS. Plain `-p` does not carry `INFO` to the back-end at all;
    # `-pp` does. A file full of correct `INFO` clauses and a `-p` invocation
    # is a reminder that is fine and plumbing that is not, and nothing reports
    # the gap.
    #
    # TODO IN A CALENDAR. `TODO`'s nagging and its overdue tail exist only in
    # Agenda Mode. In a calendar a `TODO` is an ordinary event, which makes the
    # keyword a lie about what the reminder does.
    #
    # A file with no declaration says nothing about how it is run, so this rule
    # says nothing about it either.
    class InvocationMismatch < Rule
      SORT_CHARACTERS = %w[a d].freeze

      MAX_SORT = 4

      # Where a clause was found, for a message to point at.
      Site = Struct.new(:line, :column)

      def self.default_severity
        "warning"
      end

      def self.description
        "A file whose declared `# remlint:invocation` does not deliver what it uses."
      end

      def check
        invocation = document.invocation

        if invocation.declared?
          check_sort(invocation)
          check_info(invocation)
          check_todo(invocation)
        end
      end

      private

        def check_sort(invocation)
          spec = invocation.sort_spec

          if spec && !valid_sort?(spec)
            offend(declaration_line, sort_message(spec))
          end
        end

        def valid_sort?(spec)
          spec.length <= MAX_SORT &&
            spec.each_char.all? { |character| SORT_CHARACTERS.include?(character.downcase) }
        end

        def check_info(invocation)
          clause = first_clause("INFO")

          if clause && invocation.simple_calendar? && !invocation.carries_info?
            offend(clause.line, info_message, column: clause.column)
          end
        end

        def check_todo(invocation)
          clause = first_clause("TODO")

          if clause && invocation.calendar?
            offend(clause.line, todo_message, column: clause.column)
          end
        end

        # The first command carrying a clause of that name, as a line and
        # column to point at. `filter_map` rather than an `each` with a
        # `break`, which yields the whole array when nothing matches.
        def first_clause(name)
          document.code_commands.filter_map { |command| site_of(command, name) }.first
        end

        def site_of(command, name)
          found = document.trigger_for(command).find(name)

          if found
            Site.new(*command.logical_line.position_at(found.offset))
          end
        end

        def declaration_line
          index = document.raw_lines.find_index { |raw| raw.match?(Invocation::DIRECTIVE) }

          document.line_number_at(index || 0)
        end

        def sort_message(spec)
          "`-g#{spec}` is not a sort spec Remind reads -- up to #{MAX_SORT} characters, " \
          "each `a` or `d` -- and the characters it cannot read are ignored, so the sort " \
          "never happens"
        end

        def info_message
          "this file uses `INFO`, but its declared invocation passes plain `-p`, which " \
          "does not carry headers to the back-end at all; `-pp` does"
        end

        def todo_message
          "`TODO`'s nagging and overdue tail exist only in Agenda Mode, and this file " \
          "declares a calendar invocation -- in a calendar a `TODO` is an ordinary event"
        end
    end
  end
end

__END__

require_relative "../document"

describe "RemLint::Rules::InvocationMismatch" do
  lint = proc do |text|
    source = RemLint::Source.new(path: "t.rem", text: text)

    RemLint::Rules::InvocationMismatch.new.run(RemLint::Document.new(source))
  end

  messages = proc { |text| lint.(text).map(&:message) }

  it "says nothing about a file that declares no invocation" do
    lint.(%(REM 1 Jan INFO "Url: x" TODO MSG hi\n)).should.be.empty
  end

  describe "the sort spec" do
    it "accepts a spec of a and d" do
      lint.("# remlint:invocation remind -gaad\nMSG hi\n").should.be.empty
    end

    it "accepts a bare -g" do
      lint.("# remlint:invocation remind -g\nMSG hi\n").should.be.empty
    end

    it "reports a character Remind does not read" do
      messages.("# remlint:invocation remind -gxq\nMSG hi\n").first.should.match(
        /is not a sort spec Remind reads/,
      )
    end

    it "reports a spec longer than four characters" do
      messages.("# remlint:invocation remind -gaaaaa\nMSG hi\n").length.should == 1
    end

    it "explains that the sort never happens" do
      messages.("# remlint:invocation remind -gx\nMSG hi\n").first.should.match(
        /the sort never happens/,
      )
    end
  end

  describe "INFO headers" do
    it "reports INFO under a plain -p invocation" do
      text = %(# remlint:invocation remind -p\nREM 1 Jan INFO "Url: x" MSG hi\n)

      messages.(text).first.should.match(/passes plain `-p`, which does not carry headers/)
    end

    it "accepts INFO under -pp" do
      text = %(# remlint:invocation remind -pp\nREM 1 Jan INFO "Url: x" MSG hi\n)

      lint.(text).should.be.empty
    end

    it "says nothing about a file with no INFO" do
      lint.("# remlint:invocation remind -p\nMSG hi\n").should.be.empty
    end

    it "says nothing under an agenda invocation" do
      text = %(# remlint:invocation remind -q\nREM 1 Jan INFO "Url: x" MSG hi\n)

      lint.(text).should.be.empty
    end
  end

  describe "TODO in a calendar" do
    it "reports it" do
      text = "# remlint:invocation remind -c3\nREM 1 TODO MSG File\n"

      messages.(text).first.should.match(/exist only in Agenda Mode/)
    end

    it "accepts TODO under an agenda invocation" do
      lint.("# remlint:invocation remind -q\nREM 1 TODO MSG File\n").should.be.empty
    end

    it "says nothing about a file with no TODO" do
      lint.("# remlint:invocation remind -c3\nMSG hi\n").should.be.empty
    end

    it "points at the TODO clause" do
      text = "# remlint:invocation remind -c3\nREM 1 TODO MSG File\n"

      lint.(text).first.line.should == 2
    end
  end

  it "reports every mismatch a file has" do
    text = %(# remlint:invocation remind -p -gx\nREM 1 INFO "Url: x" TODO MSG hi\n)

    lint.(text).length.should == 3
  end

  it "reports at warning severity" do
    lint.("# remlint:invocation remind -gx\nMSG hi\n").first.severity.should == "warning"
  end
end
