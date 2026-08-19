# frozen_string_literal: true

require_relative "../rule"

module RemLint
  module Rules
    # Reminder text pasted into a shell command without quotes.
    #
    # `RUN` and `INCLUDECMD` bodies go through Remind's substitution filter and
    # the result is handed to `/bin/sh`. So `%s`, `%<Location>` and `[expr]` are
    # not text in a shell command -- they are *holes* in one, and what lands in
    # them is data: a reminder body, a place name, somebody's surname.
    #
    #   REM 1 Jan RUN notify-send [msg]        # msg = "Bob's party" -> broken
    #   REM 1 Jan RUN notify-send "[msg]"      # quoted, and fine
    #
    # An apostrophe is the polite failure. `$(...)`, a backtick or a `;` in the
    # same position is a command running that nobody wrote, from a calendar,
    # under cron, with the user's own privileges. Chapter 17's own INCLUDECMD
    # example is careful to write `L="[lessons]"`; nothing enforces that care.
    #
    # This reports only what it is sure of: a substitution sitting outside any
    # quote. Quoting is tracked by walking the body character by character --
    # single quotes, double quotes, and the backslash escape inside double
    # quotes -- because that is what the shell does with it.
    #
    # A body with no substitution at all is not this rule's business: a fixed
    # `RUN echo hello` has no hole for anything to land in.
    class UnquotedShellSubstitution < Rule
      # Every hole the author did not write the contents of: the `%` sequences
      # in all their forms, and a pasted `[expr]`.
      SUBSTITUTION = /%\*?(?<simple><[^>]*>|\{[^}]*\}|\([^)]*\)|.)|\[[^\]]*\]/

      # Sequences that expand to something fixed rather than to reminder data,
      # and so are not holes:
      #
      #   %"  the calendar-text marker, which NORMAL_MODE deletes outright
      #   %%  a literal percent
      #   %_  a newline or a space
      #
      # Remind's own `tests/dedupe.rem` writes `RUN echo %"foo%"`; there is no
      # data in that command for anyone to inject through.
      CONSTANT = %w[" % _].freeze

      def self.default_severity
        "error"
      end

      def self.description
        "Reminder text pasted into a RUN or INCLUDECMD body outside shell quotes."
      end

      def check
        document.code_commands.each do |command|
          body = shell_body(command)

          if body
            report_unquoted(command, body.fetch(:text), body.fetch(:offset))
          end
        end
      end

      private

        # The shell text of the command, and where it starts in the logical
        # line, or nil if this command does not run a shell at all.
        def shell_body(command)
          if command.keyword?("INCLUDECMD")
            { text: command.args, offset: command.args_offset }
          else
            reminder_body(command)
          end
        end

        def reminder_body(command)
          trigger = document.trigger_for(command)

          if trigger.body&.name == "RUN"
            { text: command.text[trigger.body_offset..].to_s, offset: trigger.body_offset }
          end
        end

        def report_unquoted(command, text, offset)
          unquoted_spans(text).each do |span|
            offend_at(
              command.logical_line,
              offset + span.begin(0),
              "`#{span[0]}` is pasted into a shell command unquoted; " \
              "wrap it in double quotes",
            )
          end
        end

        # Every substitution in `text` that the shell would see outside quotes.
        def unquoted_spans(text)
          quoted = quote_map(text)

          text.to_enum(:scan, SUBSTITUTION).filter_map do
            match = Regexp.last_match

            unless quoted[match.begin(0)] || constant?(match)
              match
            end
          end
        end

        def constant?(match)
          CONSTANT.include?(match[:simple])
        end

        # A flag per character: is the shell inside a quote here? Walked rather
        # than pattern-matched, because whether a quote opens or closes depends
        # on every quote before it.
        def quote_map(text)
          state = nil
          escaped = false

          text.each_char.map do |character|
            inside = !state.nil?
            state, escaped = step(character, state, escaped)
            inside || !state.nil?
          end
        end

        def step(character, state, escaped)
          if escaped
            [state, false]
          elsif state == '"' && character == "\\"
            [state, true]
          elsif state.nil? && (character == "'" || character == '"')
            [character, false]
          elsif state == character
            [nil, false]
          else
            [state, false]
          end
        end
    end
  end
end

__END__

require_relative "../document"

describe "RemLint::Rules::UnquotedShellSubstitution" do
  lint = proc do |text|
    source = RemLint::Source.new(path: "t.rem", text: text)

    RemLint::Rules::UnquotedShellSubstitution.new.run(RemLint::Document.new(source))
  end

  messages = proc { |text| lint.(text).map(&:message) }

  describe "RUN bodies" do
    it "reports a bare substitution" do
      messages.("REM 1 Jan RUN notify-send %s\n").length.should == 1
      messages.("REM 1 Jan RUN notify-send %s\n").first.should.match(/`%s` is pasted/)
    end

    it "reports a bare pasted expression" do
      messages.("REM 1 Jan RUN notify-send [msg]\n").length.should == 1
    end

    it "accepts a substitution in double quotes" do
      lint.(%(REM 1 Jan RUN notify-send "%s"\n)).should.be.empty
    end

    it "accepts a substitution in single quotes" do
      lint.("REM 1 Jan RUN notify-send '%s'\n").should.be.empty
    end

    it "accepts a pasted expression in double quotes" do
      lint.(%(REM 1 Jan RUN notify-send "[msg]"\n)).should.be.empty
    end

    it "reports the second of two when only the first is quoted" do
      offenses = lint.(%(REM 1 Jan RUN cmd "%s" %t\n))

      offenses.length.should == 1
      offenses.first.message.should.match(/`%t`/)
    end

    it "is not fooled by a quote that closes before the substitution" do
      lint.(%(REM 1 Jan RUN echo "hello" %s\n)).length.should == 1
    end

    it "is not fooled by an escaped quote inside a double-quoted string" do
      # The \\" does not close the string, so %s is still inside it.
      lint.(%(REM 1 Jan RUN echo "a \\" %s"\n)).should.be.empty
    end

    it "treats an apostrophe inside double quotes as text, not a quote" do
      lint.(%(REM 1 Jan RUN echo "Bob's %s"\n)).should.be.empty
    end

    it "reports the substitution forms that take arguments" do
      messages.("REM 1 Jan RUN cmd %<Location>\n").first.should.match(/%<Location>/)
      messages.("REM 1 Jan RUN cmd %{name}\n").first.should.match(/%\{name\}/)
    end

    it "handles the %* modifier" do
      messages.("REM 1 Jan RUN cmd %*l\n").first.should.match(/`%\*l`/)
    end

    it "says nothing about a RUN body with no substitution at all" do
      lint.("REM 1 Jan RUN /usr/bin/backup --now\n").should.be.empty
    end

    it "says nothing about the sequences that expand to something fixed" do
      # Straight from tests/dedupe.rem. `%"` is the calendar-text marker and
      # NORMAL_MODE deletes it; there is no data here to inject through.
      lint.(%(REM 8 RUN echo %"foo%"\n)).should.be.empty
      lint.("REM 1 Jan RUN echo 50%% off\n").should.be.empty
    end

    it "says nothing about a command that only looks like it runs a shell" do
      # `run` here is English, and ERRMSG takes its own argument.
      lint.("ERRMSG Please run [filename()] with the -q option\n").should.be.empty
    end
  end

  describe "INCLUDECMD" do
    it "reports an unquoted paste" do
      messages.("INCLUDECMD ./lessons [lessons]\n").length.should == 1
    end

    it "accepts the quoted form the book uses" do
      lint.(%(INCLUDECMD ./gen L="[lessons]"\n)).should.be.empty
    end
  end

  describe "what it leaves alone" do
    it "says nothing about a MSG body" do
      # A MSG body is printed, not executed.
      lint.("REM 1 Jan MSG Party at [place]\n").should.be.empty
    end

    it "says nothing about a CAL or SPECIAL body" do
      lint.("REM 1 Jan CAL [place]\n").should.be.empty
      lint.("REM 1 Jan SPECIAL HTML [place]\n").should.be.empty
    end

    it "says nothing about a substitution in the trigger" do
      lint.("REM [trigger(today())] MSG hi\n").should.be.empty
    end

    it "says nothing about comments" do
      lint.("# REM 1 Jan RUN cmd %s\n").should.be.empty
    end
  end

  it "reports at error severity" do
    lint.("REM 1 Jan RUN cmd %s\n").first.severity.should == "error"
  end

  it "points at the substitution" do
    text = "REM 1 Jan RUN cmd %s\n"

    lint.(text).first.column.should == text.index("%s") + 1
  end

  it "reports the physical line inside a continuation" do
    lint.("REM 1 Jan RUN cmd \\\n    %s\n").first.line.should == 2
  end
end
