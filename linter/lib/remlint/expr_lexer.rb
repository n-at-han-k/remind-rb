# frozen_string_literal: true

require "strscan"

module RemLint
  # One lexeme of a command's body, with where it sat.
  #
  # `offset` is a character offset into the logical line's text, which
  # {LogicalLine#position_at} turns into a file line and column. Tokens carry
  # the offset rather than a line number because a continued command's tokens
  # are spread over several lines and only the offset survives the join.
  Token = Struct.new(
    :type,
    :value,
    :offset,
    keyword_init: true,
  ) do
    def length
      value.length
    end

    def end_offset
      offset + length
    end
  end

  # Tokenises the inside of a Remind command.
  #
  # Not a parser. Remind's expression grammar is real, but a linter needs far
  # less than a grammar and gets it much more cheaply: what it needs to know is
  # where the string literals are (so it does not count a `[` inside one), where
  # the bracketed expressions are, and where the function calls are. Everything
  # else can stay an undifferentiated run of characters.
  #
  # Strings matter most. `MSG see [ansicolor("")]` has balanced brackets;
  # `MSG a "]" b` does not contain a closing bracket at all. Scanning
  # characters without tracking quotes gets both wrong.
  class ExprLexer
    # Remind takes both quote characters, with backslash escaping inside.
    DOUBLE_QUOTED = /"(?:[^"\\]|\\.)*"?/
    SINGLE_QUOTED = /'(?:[^'\\]|\\.)*'?/

    # `%a`, `%_`, `%"` -- the substitution sequences, one character after the
    # percent. Matched before anything else can claim the character, which is
    # what remind.vim's `remindSubst` pattern does.
    SUBSTITUTION = /%[^\s]/

    # `$SysInclude`, `$Latitude`.
    SYSVAR = /\$[A-Za-z_]\w*/

    # A name immediately followed by `(` is a call; a name not followed by one
    # is a variable read, and the two need different rules applied to them.
    FUNCTION = /[A-Za-z_]\w*(?=\()/
    NAME     = /[A-Za-z_]\w*/

    NUMBER = /\d+(?:\.\d+)?/

    WHITESPACE = /\s+/

    def initialize(text)
      @scanner = StringScanner.new(text)
    end

    def self.tokenise(text)
      new(text).tokenise
    end

    def tokenise
      [].tap do |tokens|
        until @scanner.eos?
          tokens << next_token
        end
      end
    end

    # Just the tokens that carry meaning -- everything but whitespace.
    def self.significant(text)
      tokenise(text).reject { |token| token.type == :whitespace }
    end

    private

      # Ordered by specificity, not by frequency: a `%` that opens a
      # substitution must not be read as an operator, and a name before `(`
      # must not be read as a bare name.
      def next_token
        emit(:string,       DOUBLE_QUOTED) ||
          emit(:string,     SINGLE_QUOTED) ||
          emit(:whitespace, WHITESPACE) ||
          emit(:lbracket,   /\[/) ||
          emit(:rbracket,   /\]/) ||
          emit(:lparen,     /\(/) ||
          emit(:rparen,     /\)/) ||
          emit(:comma,      /,/) ||
          emit(:substitution, SUBSTITUTION) ||
          emit(:sysvar,     SYSVAR) ||
          emit(:function,   FUNCTION) ||
          emit(:name,       NAME) ||
          emit(:number,     NUMBER) ||
          single_character
      end

      def emit(type, pattern)
        offset = @scanner.pos
        value = @scanner.scan(pattern)

        if value
          Token.new(type: type, value: value, offset: offset)
        end
      end

      # Operators, punctuation and anything else: one character, unclassified.
      # A rule that cares can look at the value.
      def single_character
        offset = @scanner.pos

        Token.new(type: :other, value: @scanner.getch, offset: offset)
      end
  end
end

__END__

describe "RemLint::ExprLexer" do
  lex = proc { |text| RemLint::ExprLexer.significant(text) }
  types = proc { |text| lex.(text).map(&:type) }
  values = proc { |text| lex.(text).map(&:value) }

  it "keeps whitespace in the full stream and drops it from the significant one" do
    RemLint::ExprLexer.tokenise("a b").map(&:type).should == %i[name whitespace name]
    types.("a b").should == %i[name name]
  end

  it "records the offset of every token" do
    tokens = lex.("MSG [x]")

    tokens.map(&:offset).should == [0, 4, 5, 6]
    tokens.last.end_offset.should == 7
  end

  describe "strings" do
    it "takes a double-quoted string whole" do
      values.(%(a "hello world" b)).should == ["a", %("hello world"), "b"]
    end

    it "takes a single-quoted string whole, as Remind's date literals need" do
      values.("x '2026-01-01' y").should == ["x", "'2026-01-01'", "y"]
    end

    it "honours backslash escapes inside a string" do
      values.(%("a \\" b" c)).should == [%("a \\" b"), "c"]
    end

    it "does not let a bracket inside a string count as a bracket" do
      types.(%(MSG "]" done)).should == %i[name string name]
    end

    it "runs an unterminated string to end of line rather than looping" do
      values.(%(MSG "oops)).should == ["MSG", %("oops)]
    end
  end

  describe "Remind's sigils" do
    it "recognises system variables" do
      types.("INCLUDE [$SysInclude]/ansitext.rem").should ==
        %i[name lbracket sysvar rbracket other name other name]
    end

    it "recognises a substitution as the percent plus one character" do
      values.("MSG at %2 on %_").should == ["MSG", "at", "%2", "on", "%_"]
    end

    it "does not read a percent before a space as a substitution" do
      types.("BANNER % ").should == %i[name other]
    end
  end

  describe "calls" do
    it "distinguishes a call from a bare name" do
      types.("trigger(x)").should == %i[function lparen name rparen]
      types.("trigger").should == %i[name]
    end

    it "lexes a nested call" do
      values.("[ansicolor(0,255,0) + center(x)]").should ==
        ["[", "ansicolor", "(", "0", ",", "255", ",", "0", ")", "+", "center", "(", "x", ")", "]"]
    end
  end

  it "gives every other character its own token rather than dropping it" do
    types.("a >= b").should == %i[name other other name]
  end

  it "lexes across the newlines a joined command carries" do
    types.("IF a && \n   b").should == %i[name name other other name]
  end
end
