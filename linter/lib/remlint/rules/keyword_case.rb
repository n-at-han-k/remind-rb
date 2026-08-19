# frozen_string_literal: true

require_relative "../rule"

module RemLint
  module Rules
    # Command keywords written in a case the file does not otherwise use.
    #
    # Remind's keywords are case-insensitive -- `remind.vim` opens with
    # `syn case ignore` for exactly this reason -- so this is a consistency
    # rule and nothing more. It is off by default: `examples/alignment.rem`
    # deliberately mixes `MSG` and `msg` to show the two are the same, and a
    # linter that shouts at the shipped examples for their own subject matter
    # is a linter people switch off.
    #
    # `EnforcedStyle: upper` (the default when the rule is on) matches every
    # example Remind ships and the manual's own prose. `lower` is the mirror
    # image. `consistent` picks whichever style the file already uses more and
    # reports the rest, which is the setting for adopting the rule on a file
    # you did not write.
    class KeywordCase < Rule
      STYLES = %w[upper lower consistent].freeze

      def self.enabled_by_default?
        false
      end

      def self.description
        "Command keywords in a case other than the file's own."
      end

      def check
        style = resolve_style

        keyword_commands.each do |command|
          if !conforms?(command.word, style)
            offend(
              command.line,
              "Write `#{cased(command.word, style)}` rather than `#{command.word}`",
              column: command.keyword_column,
            )
          end
        end
      end

      private

        def keyword_commands
          document.code_commands.select { |command| command.kind == :keyword }
        end

        def resolve_style
          configured = option("EnforcedStyle", "upper")

          if configured == "consistent"
            majority_style
          else
            configured
          end
        end

        # Whichever style already accounts for more of the file's keywords, so
        # turning the rule on reports the minority rather than half the file.
        # A tie goes to upper, which is what Remind's own examples use.
        def majority_style
          words = keyword_commands.map(&:word)
          lower = words.count { |word| word == word.downcase }
          upper = words.count { |word| word == word.upcase }

          if lower > upper
            "lower"
          else
            "upper"
          end
        end

        def conforms?(word, style)
          word == cased(word, style)
        end

        def cased(word, style)
          if style == "lower"
            word.downcase
          else
            word.upcase
          end
        end
    end
  end
end

__END__

require_relative "../document"

describe "RemLint::Rules::KeywordCase" do
  lint = proc do |text, config = {}|
    source = RemLint::Source.new(path: "t.rem", text: text)

    RemLint::Rules::KeywordCase.new(config).run(RemLint::Document.new(source))
  end

  messages = proc { |text, config = {}| lint.(text, config).map(&:message) }

  it "is off unless the configuration asks for it" do
    RemLint::Rules::KeywordCase.enabled_by_default?.should.be.false
  end

  describe "the default upper style" do
    it "accepts upper-case keywords" do
      lint.("SET a 1\nMSG hi\n").should.be.empty
    end

    it "reports a lower-case keyword" do
      messages.("msg hi\n").should == ["Write `MSG` rather than `msg`"]
    end

    it "reports a mixed-case keyword" do
      messages.("MsG hi\n").should == ["Write `MSG` rather than `MsG`"]
    end

    it "reports the abbreviation as written, not expanded" do
      messages.("inc defs.rem\n").should == ["Write `INC` rather than `inc`"]
    end

    it "points at the keyword's column" do
      lint.("   msg hi\n").first.column.should == 4
    end
  end

  describe "the lower style" do
    it "reports an upper-case keyword" do
      messages.("MSG hi\n", "EnforcedStyle" => "lower").should ==
        ["Write `msg` rather than `MSG`"]
    end

    it "accepts lower-case keywords" do
      lint.("msg hi\n", "EnforcedStyle" => "lower").should.be.empty
    end
  end

  describe "the consistent style" do
    consistent = { "EnforcedStyle" => "consistent" }

    it "reports the minority when the file is mostly upper" do
      messages.("MSG a\nMSG b\nmsg c\n", consistent).should == ["Write `MSG` rather than `msg`"]
    end

    it "reports the minority when the file is mostly lower" do
      messages.("msg a\nmsg b\nMSG c\n", consistent).should == ["Write `msg` rather than `MSG`"]
    end

    it "prefers upper on a tie, as Remind's own examples do" do
      messages.("MSG a\nmsg b\n", consistent).should == ["Write `MSG` rather than `msg`"]
    end
  end

  describe "what it stays quiet about" do
    it "says nothing about a trigger with no keyword" do
      lint.("1 Nov ++12 MSG get ready\n").should.be.empty
    end

    it "says nothing about clause keywords inside a trigger" do
      # Only the command's own keyword is this rule's business.
      lint.("REM 1 Jan until 3 Jan MSG hi\n").should.be.empty
    end

    it "says nothing about comments or blank lines" do
      lint.("# msg\n\n").should.be.empty
    end
  end
end
