# frozen_string_literal: true

require_relative "../rule"
require_relative "../vocabulary"

module RemLint
  module Rules
    # `$Names` Remind does not have.
    #
    # Remind's system-variable namespace is closed: `FindSysVar` binary-searches
    # a fixed table and anything missing is `E_NOSUCH_VAR` (src/var.c). So a
    # typo here is never a variable that happens to be empty -- it is an error,
    # and one that fires only when the line runs, which for a reminder can be
    # months away.
    #
    # The one exception the rule has to know about is `-i` on the command line:
    # `remind -i$Latitude="..."` initialises a variable that is not in the
    # table, and `examples/astro` does exactly that in all four of its heredocs.
    # Those come in as ordinary user variables without the sigil, so they do not
    # reach this rule -- but a file that names its own `$`-prefixed variables
    # can list them under `AllowedNames`.
    class UnknownSystemVariable < Rule
      def self.default_severity
        "error"
      end

      def self.description
        "A $SystemVariable that is not one of Remind's."
      end

      def check
        allowed = option("AllowedNames", []).map(&:downcase)

        document.logical_lines.each_with_index do |logical_line, index|
          if document.commands[index].code?
            check_line(logical_line, allowed)
          end
        end
      end

      private

        def check_line(logical_line, allowed)
          document.tokens_for(logical_line).each do |token|
            if unknown?(token, allowed)
              offend_at(logical_line, token.offset, "`#{token.value}` is not a Remind system variable")
            end
          end
        end

        def unknown?(token, allowed)
          token.type == :sysvar &&
            Vocabulary.sysvar(token.value).nil? &&
            !allowed.include?(token.value.delete_prefix("$").downcase)
        end
    end
  end
end

__END__

require_relative "../document"

describe "RemLint::Rules::UnknownSystemVariable" do
  lint = proc do |text, config = {}|
    source = RemLint::Source.new(path: "t.rem", text: text)

    RemLint::Rules::UnknownSystemVariable.new(config).run(RemLint::Document.new(source))
  end

  messages = proc { |text, config = {}| lint.(text, config).map(&:message) }

  describe "variables Remind has" do
    it "accepts one in a SET" do
      lint.("SET $AddBlankLines 0\n").should.be.empty
    end

    it "accepts one in a bracketed expression" do
      lint.("INCLUDE [$SysInclude]/ansitext.rem\n").should.be.empty
    end

    it "accepts one whatever its case, as FindSysVar does" do
      lint.("SET $addblanklines 0\n").should.be.empty
      lint.("SET $ADDBLANKLINES 0\n").should.be.empty
    end

    it "accepts the trigger variables" do
      lint.("MSG [$T] and [$U]\n").should.be.empty
    end
  end

  describe "variables Remind does not have" do
    it "reports a typo" do
      messages.("SET $AddBlankLine 0\n").should == ["`$AddBlankLine` is not a Remind system variable"]
    end

    it "points at the sigil" do
      lint.("SET $Nope 1\n").first.column.should == 5
    end

    it "reports every one on a line" do
      messages.("MSG [$Nope] and [$AlsoNope]\n").length.should == 2
    end

    it "reports at error severity" do
      lint.("SET $Nope 1\n").first.severity.should == "error"
    end
  end

  describe "what it stays quiet about" do
    it "says nothing about a plain variable with no sigil" do
      lint.("SET Latitude \"45.42\"\n").should.be.empty
    end

    it "says nothing about a name inside a string" do
      lint.(%(MSG "costs $Nope dollars"\n)).should.be.empty
    end

    it "says nothing about comments" do
      lint.("# uses $Nope somewhere\n").should.be.empty
    end

    it "says nothing about a bare dollar sign" do
      lint.("RUN echo $ done\n").should.be.empty
    end
  end

  describe "AllowedNames" do
    it "accepts a name the configuration allows" do
      lint.("MSG [$Latitude]\n", "AllowedNames" => ["Latitude"]).should.be.empty
    end

    it "matches an allowed name case-insensitively" do
      lint.("MSG [$latitude]\n", "AllowedNames" => ["Latitude"]).should.be.empty
    end

    it "still reports the names it does not allow" do
      messages.("MSG [$Latitude] [$Nope]\n", "AllowedNames" => ["Latitude"]).length.should == 1
    end
  end

  it "reports the physical line inside a continuation" do
    lint.("SET x 1 + \\\n    $Nope\n").first.line.should == 2
  end
end
