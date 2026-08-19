# frozen_string_literal: true

require_relative "../rule"

module RemLint
  module Rules
    # `%` sequences Remind does not substitute.
    #
    # Narrower than it first looks, and the narrowing is worth stating. The set
    # in `dosubst.c` is closed but *wide*: the switch is on `UPPER(c)`, and
    # every one of the twenty-six letters and all ten digits is a case. So
    # there is no `%z` typo to catch -- `%z` is the seconds-since-epoch
    # sequence. What is left to report is punctuation, and the argument forms
    # that were opened and never closed.
    #
    # It is worth reporting because the failure is invisible. The `default:`
    # branch emits the character *and drops the percent*: `%~` prints `~`, with
    # no error, no warning, and nothing to distinguish it from text somebody
    # meant to type.
    #
    # Four sequences take an argument rather than a single character, and all
    # four are recognised here so their contents are not mistaken for the
    # sequence itself:
    #
    #   %<Header>   an INFO header      (silently empty when absent)
    #   %{name}     calls subst_name    (warns only at warning level 05.00.03)
    #   %(text)     a translated string
    #   %*x         the alternate-mode modifier, then a real sequence
    #
    # Leaving one of the first three unterminated is a warning from Remind at
    # run time; reporting it here says the same thing without running the file.
    #
    # A `%` at the very end of a body is *not* an error. It suppresses the
    # newline Remind would otherwise append -- `dosubst("hello")` is six
    # characters and `dosubst("hello%")` is five (remind.1: "if str does not
    # end with %, a newline character will be added"). Remind's own
    # tests/test.rem ends 160 bodies that way.
    #
    # Only reminder bodies are checked. Elsewhere on a line a `%` is an
    # ordinary character -- `BANNER %` is the idiom for no banner at all.
    class UnknownSubstitutionSequence < Rule
      # From the `switch (UPPER(c))` in src/dosubst.c. Every letter and every
      # digit is a case; the punctuation is the part that is actually a set.
      LETTERS = ("A".."Z").to_a.freeze
      DIGITS = ("0".."9").to_a.freeze
      PUNCTUATION = %w[! ? @ # : _ "].freeze

      # `%%` has no case of its own, but the default branch emits the second
      # `%` -- so it is the working way to write a literal percent, and
      # reporting it would be reporting the fix.
      LITERAL_PERCENT = "%"

      SIMPLE = (LETTERS + DIGITS + PUNCTUATION + [LITERAL_PERCENT]).freeze

      # A trailing `%` suppresses the newline; the regex reports it as an empty
      # body, because there is no character after the percent to report.
      TRAILING = ""

      # An opener with no closer before end of body. Remind warns about each of
      # these at run time ("Unterminated %<...> substitution sequence").
      UNTERMINATED = { "<" => ">", "{" => "}", "(" => ")" }.freeze

      # The whole sequence, in every form, so the scan advances past an
      # argument rather than stopping inside it.
      SEQUENCE = /%(?<modifier>\*?)(?<body><[^>]*>|\{[^}]*\}|\([^)]*\)|.|\z)/

      ARGUMENT_FORMS = /\A[<{(]/

      def self.default_severity
        "warning"
      end

      def self.description
        "A % sequence in a reminder body that Remind does not substitute."
      end

      def check
        document.code_commands.each do |command|
          body = body_of(command)

          if body
            report(command, body.fetch(:text), body.fetch(:offset))
          end
        end
      end

      private

        def body_of(command)
          trigger = document.trigger_for(command)

          if trigger.text_body?
            { text: command.text[trigger.body_offset..].to_s, offset: trigger.body_offset }
          end
        end

        def report(command, text, offset)
          text.to_enum(:scan, SEQUENCE).each do
            match = Regexp.last_match

            unless recognised?(match[:body])
              offend_at(command.logical_line, offset + match.begin(0), message_for(match))
            end
          end
        end

        # A complete argument form, or a single character in the set. An
        # unterminated `%<` arrives here as the one character `<`, which is
        # exactly what distinguishes it from a closed `%<Header>`.
        def recognised?(body)
          body == TRAILING ||
            (body.length > 1 && body.match?(ARGUMENT_FORMS)) ||
            SIMPLE.include?(body.upcase)
        end

        def message_for(match)
          body = match[:body]
          closer = UNTERMINATED[body]

          if closer
            "`%#{body}` is never closed by `#{closer}`"
          else
            "`%#{match[:modifier]}#{body}` is not a substitution sequence; " \
            "Remind drops the `%` and prints `#{body}`"
          end
        end
    end
  end
end

__END__

require_relative "../document"

describe "RemLint::Rules::UnknownSubstitutionSequence" do
  lint = proc do |text|
    source = RemLint::Source.new(path: "t.rem", text: text)

    RemLint::Rules::UnknownSubstitutionSequence.new.run(RemLint::Document.new(source))
  end

  messages = proc { |text| lint.(text).map(&:message) }

  describe "sequences Remind has" do
    it "accepts the letter sequences in either case" do
      lint.("REM 1 Jan MSG Birthday %a and %B and %c\n").should.be.empty
    end

    it "accepts the digit sequences" do
      lint.("REM 1 Jan AT 15:00 MSG Meeting %1 %2 %3 %0\n").should.be.empty
    end

    it "accepts the punctuation sequences" do
      lint.(%(REM 1 Jan MSG a %! b %? c %@ d %# e %: f %_ g\n)).should.be.empty
    end

    it "accepts the calendar-text delimiter" do
      lint.(%{REM 1 Jan MSG %"Bob's birthday%" is %b\n}).should.be.empty
    end

    it "accepts the alternate-mode modifier" do
      lint.("REM 1 Jan MSG %*l and %*3\n").should.be.empty
    end
  end

  describe "the argument-taking forms" do
    it "accepts an INFO header reference" do
      lint.("REM 1 Jan INFO \"Location: pub\" MSG Meet at %<Location>\n").should.be.empty
    end

    it "accepts a substitution-callback call" do
      lint.("REM 1 Jan MSG %{ordinal} of the month\n").should.be.empty
    end

    it "accepts a translated string" do
      lint.("REM 1 Jan MSG %(Happy birthday)\n").should.be.empty
    end

    it "does not read the contents of an argument as sequences" do
      # The ~ inside the braces is part of a function name, not a sequence.
      lint.("REM 1 Jan MSG %{a~b}\n").should.be.empty
    end

    it "reports an unterminated argument form" do
      messages.("REM 1 Jan MSG Meet at %<Location\n").first.should ==
        "`%<` is never closed by `>`"
      messages.("REM 1 Jan MSG %{ordinal\n").first.should == "`%{` is never closed by `}`"
      messages.("REM 1 Jan MSG %(hello\n").first.should == "`%(` is never closed by `)`"
    end
  end

  describe "sequences Remind does not have" do
    it "reports an unknown punctuation mark" do
      messages.("REM 1 Jan MSG See %~ here\n").first.should ==
        "`%~` is not a substitution sequence; Remind drops the `%` and prints `~`"
    end

    it "reports each one on a line" do
      messages.("REM 1 Jan MSG %~ and %$\n").length.should == 2
    end

    it "points at the percent" do
      text = "REM 1 Jan MSG See %~ here\n"

      lint.(text).first.column.should == text.index("%~") + 1
    end

    it "accepts every letter, because every letter is a real sequence" do
      body = ("a".."z").map { |letter| "%#{letter}" }.join(" ")

      lint.("REM 1 Jan AT 15:00 MSG #{body}\n").should.be.empty
    end

    it "accepts %% as the literal percent it is" do
      # No case of its own, but the default branch emits the second `%`.
      lint.("REM 1 Jan MSG 50%% off\n").should.be.empty
    end

    it "accepts a trailing percent, which suppresses the appended newline" do
      # Documented in remind.1, and used 160 times in Remind's own test.rem.
      lint.("REM 1 Jan MSG all done %\n").should.be.empty
    end
  end

  describe "where it does not look" do
    it "says nothing about a percent in the trigger" do
      lint.("REM 1 Jan MSG hi\n").should.be.empty
    end

    it "says nothing about BANNER %" do
      # The idiom for no banner at all, and not a reminder body.
      lint.("BANNER %\n").should.be.empty
    end

    it "says nothing about a percent in a comment" do
      lint.("# 50% done\n").should.be.empty
    end

    it "says nothing about a command with no body" do
      lint.("SET a 50\n").should.be.empty
    end
  end

  it "checks a RUN body too" do
    messages.("REM 1 Jan RUN echo %~\n").length.should == 1
  end

  it "reports at warning severity" do
    lint.("REM 1 Jan MSG %~\n").first.severity.should == "warning"
  end

  it "reports the physical line inside a continuation" do
    lint.("REM 1 Jan MSG a \\\n    %~\n").first.line.should == 2
  end
end
