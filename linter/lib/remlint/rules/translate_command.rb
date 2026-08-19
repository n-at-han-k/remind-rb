# frozen_string_literal: true

require_relative "../rule"

module RemLint
  module Rules
    # `TRANSLATE` commands Remind will not accept, or will reject silently.
    #
    # `TRANSLATE` has five forms and nothing else parses:
    #
    #   TRANSLATE "original" "translated"
    #   TRANSLATE "original"            (removes one)
    #   TRANSLATE CLEAR
    #   TRANSLATE DUMP
    #   TRANSLATE LOAD "file"
    #
    # The bare-word forms are the ones that go wrong, because they are one
    # forgotten pair of quotes away from being a translation *of* the literal
    # string "CLEAR".
    #
    # The other half is the one that matters to a translator. A translated
    # string has to carry the same `%` escapes as the original, in the same
    # order -- Remind compares them and refuses the translation outright if
    # they differ. The message then stays in English, which looks like a
    # missing translation rather than a rejected one.
    class TranslateCommand < Rule
      BARE_WORDS = %w[CLEAR DUMP].freeze

      LOAD = "LOAD"

      # `%a`, `%*b`, `%<Header>` and the rest -- anything the substitution
      # filter would replace, which both sides have to agree on.
      ESCAPE = /%\*?(?:<[^>]*>|\{[^}]*\}|\([^)]*\)|.)/

      STRING = /\A\s*"(?:[^"\\]|\\.)*"/

      def self.default_severity
        "warning"
      end

      def self.description
        "A TRANSLATE that is not one of Remind's five forms, or whose escapes do not match."
      end

      def check
        document.code_commands.each do |command|
          if command.keyword?("TRANSLATE")
            check_command(command)
          end
        end
      end

      private

        def check_command(command)
          args = command.args.strip
          word = args[/\A\S+/].to_s.upcase

          if BARE_WORDS.include?(word) || word == LOAD
            nil
          else
            check_strings(command, args)
          end
        end

        def check_strings(command, args)
          strings = quoted(args)

          if strings.empty?
            offend(command.line, form_message(args), column: command.keyword_column)
          elsif strings.length >= 2
            compare(command, strings[0], strings[1])
          end
        end

        # The one or two quoted strings the command carries.
        def quoted(args)
          rest = args.dup
          found = []

          while (match = rest.match(STRING))
            found << match[0].strip
            rest = match.post_match
          end

          found
        end

        def compare(command, original, translated)
          from = original.scan(ESCAPE)
          to = translated.scan(ESCAPE)

          if from != to
            offend(command.line, escape_message(from, to), column: command.keyword_column)
          end
        end

        def form_message(args)
          "`TRANSLATE #{args.split(/\s+/).first}` is none of Remind's five forms; it takes " \
          "a quoted string, two quoted strings, `CLEAR`, `DUMP`, or `LOAD \"file\"`"
        end

        def escape_message(from, to)
          "the translation carries #{describe(to)} where the original has #{describe(from)}; " \
          "Remind compares them and rejects a translation whose escapes differ, leaving " \
          "the message in English"
        end

        def describe(escapes)
          if escapes.empty?
            "none"
          else
            escapes.map { |escape| "`#{escape}`" }.join(" ")
          end
        end
    end
  end
end

__END__

require_relative "../document"

describe "RemLint::Rules::TranslateCommand" do
  lint = proc do |text|
    source = RemLint::Source.new(path: "t.rem", text: text)

    RemLint::Rules::TranslateCommand.new.run(RemLint::Document.new(source))
  end

  messages = proc { |text| lint.(text).map(&:message) }

  describe "the five forms" do
    it "accepts two quoted strings" do
      lint.(%(TRANSLATE "Monday" "Montag"\n)).should.be.empty
    end

    it "accepts one quoted string" do
      lint.(%(TRANSLATE "Monday"\n)).should.be.empty
    end

    it "accepts CLEAR and DUMP" do
      lint.("TRANSLATE CLEAR\n").should.be.empty
      lint.("TRANSLATE DUMP\n").should.be.empty
    end

    it "accepts LOAD with a filename" do
      lint.(%(TRANSLATE LOAD "de.rem"\n)).should.be.empty
    end

    it "accepts the bare words in lower case" do
      lint.("translate clear\n").should.be.empty
    end

    it "reports anything else" do
      messages.("TRANSLATE Monday Montag\n").first.should.match(
        /is none of Remind's five forms/,
      )
    end
  end

  describe "escapes that do not match" do
    it "reports a missing escape" do
      messages.(%(TRANSLATE "in %b" "in"\n)).first.should.match(
        /carries none where the original has `%b`/,
      )
    end

    it "reports an added escape" do
      messages.(%(TRANSLATE "today" "heute %b"\n)).first.should.match(/carries `%b`/)
    end

    it "reports escapes in a different order" do
      messages.(%(TRANSLATE "%a and %b" "%b und %a"\n)).first.should.match(
        /carries `%b` `%a` where the original has `%a` `%b`/,
      )
    end

    it "accepts matching escapes" do
      lint.(%(TRANSLATE "%a and %b" "%a und %b"\n)).should.be.empty
    end

    it "accepts two strings with no escapes at all" do
      lint.(%(TRANSLATE "Monday" "Montag"\n)).should.be.empty
    end

    it "explains what Remind does about it" do
      messages.(%(TRANSLATE "in %b" "in"\n)).first.should.match(/leaving the message in English/)
    end
  end

  it "says nothing about comments" do
    lint.("# TRANSLATE Monday Montag\n").should.be.empty
  end

  it "points at the keyword" do
    lint.("   TRANSLATE Monday Montag\n").first.column.should == 4
  end

  it "reports at warning severity" do
    lint.("TRANSLATE Monday Montag\n").first.severity.should == "warning"
  end
end
