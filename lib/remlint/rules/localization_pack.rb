# frozen_string_literal: true

require_relative "../rule"

module RemLint
  module Rules
    # A language pack that never translates `LANGID`.
    #
    # Scripts branch on `_("LANGID")` to pick language-specific behaviour, and
    # an untranslated LANGID reverts to `"en"`. So a fully translated pack that
    # never translates LANGID sends every one of those scripts down the English
    # path -- and does it by producing English, which reads as "not translated
    # yet" rather than "translated and ignored".
    #
    # A pack is recognised by its day and month names, which is what
    # `include/lang/*.rem` set and what nothing else does. A file translating a
    # handful of strings -- `include/translations/de/sun.rem` is two lines --
    # is not a pack and has no LANGID to translate.
    class LocalizationPack < Rule
      LANGID = "LANGID"

      # What a language pack sets and a string file does not.
      PACK_NAMES = (
        %w[monday tuesday wednesday thursday friday saturday sunday] +
        %w[january february march april may june july
           august september october november december
]
      ).freeze

      TRANSLATED = /\A\s*"(?<original>(?:[^"\\]|\\.)*)"\s*"/

      SYSVAR_SET = /\A\$(?<name>\w+)\s/

      def self.default_severity
        "info"
      end

      def self.description
        "A language pack that never translates LANGID, which reverts to English."
      end

      def check
        if pack?
          check_langid
        end
      end

      private

        # A pack names the days and months. `include/lang/de.rem` writes
        # `SET $Monday "Montag"`; a translation file writes neither.
        def pack?
          document.code_commands.any? { |command| names_a_day_or_month?(command) }
        end

        def names_a_day_or_month?(command)
          if command.keyword?("SET")
            match = command.args.match(SYSVAR_SET)

            !match.nil? && PACK_NAMES.include?(match[:name].downcase)
          elsif command.keyword?("TRANSLATE")
            original = command.args.match(TRANSLATED)&.[](:original)

            PACK_NAMES.include?(original.to_s.downcase)
          end
        end

        def check_langid
          unless translates_langid?
            offend(
              document.line_number_at(0),
              "this pack never translates `#{LANGID}`, which reverts to `\"en\"` -- so " \
              "every script branching on `_(\"#{LANGID}\")` takes the English path",
            )
          end
        end

        def translates_langid?
          document.code_commands.any? do |command|
            command.keyword?("TRANSLATE") &&
              command.args.match(TRANSLATED)&.[](:original) == LANGID
          end
        end
    end
  end
end

__END__

require_relative "../document"

describe "RemLint::Rules::LocalizationPack" do
  lint = proc do |text|
    source = RemLint::Source.new(path: "t.rem", text: text)

    RemLint::Rules::LocalizationPack.new.run(RemLint::Document.new(source))
  end

  messages = proc { |text| lint.(text).map(&:message) }

  describe "LANGID" do
    it "reports a pack that never translates it" do
      messages.(%(TRANSLATE "Monday" "Montag"\n)).first.should.match(
        /never translates `LANGID`, which reverts to `"en"`/,
      )
    end

    it "accepts a pack that does" do
      text = %(TRANSLATE "LANGID" "de"\nTRANSLATE "Monday" "Montag"\n)

      lint.(text).should.be.empty
    end

    it "says nothing about a file that translates nothing" do
      lint.("REM 1 Jan MSG hi\n").should.be.empty
    end

    it "recognises a pack by the day and month names it sets" do
      # include/lang/de.rem writes SET $Monday "Montag" rather than TRANSLATE.
      messages.(%(SET $Monday "Montag"\n)).length.should == 1
      lint.(%(SET $Monday "Montag"\nTRANSLATE "LANGID" "de"\n)).should.be.empty
    end

    it "does not count a file that translates a handful of strings" do
      # include/translations/de/sun.rem is exactly this, and is not a pack.
      lint.(%(TRANSLATE "Sunrise" "Sonnenaufgang"\nTRANSLATE "Sunset" "Sonnenuntergang"\n))
        .should.be.empty
    end

    it "explains the consequence" do
      messages.(%(TRANSLATE "Monday" "Montag"\n)).first.should.match(
        /takes the English path/,
      )
    end
  end

  it "says nothing about comments" do
    lint.(%(# TRANSLATE "Monday" "Montag"\n)).should.be.empty
  end

  it "reports at info severity" do
    lint.(%(TRANSLATE "Monday" "Montag"\n)).first.severity.should == "info"
  end
end
