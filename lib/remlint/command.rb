# frozen_string_literal: true

require_relative "logical_line"
require_relative "vocabulary"

module RemLint
  # A classified logical line: which keyword opens it, and what follows.
  #
  # `keyword` is nil for three different things, and rules must not confuse
  # them, so ask rather than test for nil:
  #
  #   blank?    nothing but whitespace
  #   comment?  opens with `#` or `;`
  #   implicit? a trigger with the `REM` left off -- `1 Nov ++12 MSG ...`,
  #             which the manual explicitly allows and which is the ordinary
  #             way to write a reminder
  Command = Struct.new(
    :keyword,
    :word,
    :args,
    :logical_line,
    :kind,
    keyword_init: true,
  ) do
    # Where `args` begins in `text`. `args` is always a suffix of `text`, so a
    # rule that found something at offset N in `args` can hand
    # `args_offset + N` to LogicalLine#position_at and get a real file position.
    def args_offset
      text.length - args.length
    end

    def line
      logical_line.line
    end

    def last_line
      logical_line.last_line
    end

    def text
      logical_line.text
    end

    def blank?
      kind == :blank
    end

    def comment?
      kind == :comment
    end

    # A command line that opens with no recognisable keyword. Remind reads it
    # as a bare trigger with an implicit `REM`.
    def implicit?
      kind == :implicit
    end

    # Blank lines and comments are not commands at all.
    def code?
      kind == :keyword || kind == :implicit
    end

    def keyword?(*names)
      !keyword.nil? && names.map(&:upcase).include?(keyword.name)
    end

    # The column, 1-based, where the keyword itself starts.
    def keyword_column
      (text.index(/\S/) || 0) + 1
    end
  end

  # Splits a logical line into its opening keyword and the rest.
  #
  # Deliberately shallow: Remind's grammar is loose enough that a full parse
  # would be a second implementation of Remind, and wrong in different places
  # than the first. Rules that need to look inside `args` reach for
  # {ExprLexer}; rules that only care which command this is stop here.
  module Classifier
    COMMENT = /\A\s*[#;]/
    BLANK   = /\A\s*\z/m
    WORD    = /\A\s*(\S+)/

    module_function

    def call(logical_line)
      text = logical_line.text

      if text.match?(BLANK)
        bare(logical_line, :blank)
      elsif text.match?(COMMENT)
        bare(logical_line, :comment)
      else
        classify_code(logical_line, text)
      end
    end

    def all(logical_lines)
      logical_lines.map { |logical_line| call(logical_line) }
    end

    # A line opening with a clause keyword -- a month, a weekday, an ordinal --
    # is a trigger with the `REM` left off, not a command named `JANUARY`. It
    # gets `kind: :implicit` like a line opening with a bare day number, and
    # keeps its whole text as `args`, because the clause is part of the trigger
    # rather than something the command takes.
    def classify_code(logical_line, text)
      match = text.match(WORD)
      word = match[1]
      keyword = Vocabulary.keyword(word)
      commands = !keyword.nil? && !keyword.clause?

      Command.new(
        keyword:      keyword,
        word:         word,
        args:         commands ? match.post_match.sub(/\A[ \t]+/, "") : text.sub(/\A\s*/, ""),
        logical_line: logical_line,
        kind:         commands ? :keyword : :implicit,
      )
    end

    def bare(logical_line, kind)
      Command.new(
        keyword:      nil,
        word:         nil,
        args:         logical_line.text,
        logical_line: logical_line,
        kind:         kind,
      )
    end
  end
end

__END__

describe "RemLint::Classifier" do
  classify = proc do |text|
    source = RemLint::Source.new(path: "t.rem", text: text)

    RemLint::Classifier.all(RemLint::Joiner.call(source))
  end

  one = proc { |text| classify.(text).first }

  it "recognises a keyword and splits off its arguments" do
    command = one.("REM 1 Jan MSG New Year")

    command.keyword.name.should == "REM"
    command.args.should == "1 Jan MSG New Year"
    command.should.be.code
  end

  it "recognises a keyword whatever its case" do
    one.("msg hello").keyword.name.should == "MSG"
    one.("MsG hello").keyword.name.should == "MSG"
  end

  it "recognises an abbreviated keyword" do
    one.("INC defs.rem").keyword.name.should == "INCLUDE"
  end

  it "treats a bare trigger as an implicit REM" do
    command = one.("1 Nov ++12 MSG Get ready")

    command.keyword.should.be.nil
    command.should.be.implicit
    command.should.be.code
    command.args.should == "1 Nov ++12 MSG Get ready"
  end

  it "treats a trigger opening with a clause keyword as an implicit REM too" do
    command = one.("Nov 1 MSG All Saints")

    command.should.be.implicit
    command.keyword.name.should == "NOVEMBER"
    command.args.should == "Nov 1 MSG All Saints"
  end

  it "marks comments, in both of Remind's comment characters" do
    one.("# a note").should.be.comment
    one.("; also a note").should.be.comment
    one.("   # indented").should.be.comment
    one.("# a note").code?.should.be.false
  end

  it "marks blank lines" do
    one.("\n").should.be.blank
    one.("   \t \n").should.be.blank
    one.("\n").code?.should.be.false
  end

  it "can map an offset in args back to a file position" do
    command = one.("   SET x 12345")

    command.args.should == "x 12345"
    command.logical_line.position_at(command.args_offset).should == [1, 8]
  end

  it "does not mistake a trailing # for a comment" do
    one.("MSG see issue #42").should.be.code
  end

  it "keeps the logical line, so continued commands classify once" do
    commands = classify.("IF a > 1 && \\\n   b < 2\nENDIF\n")

    commands.length.should == 2
    commands.first.keyword.name.should == "IF"
    commands.first.line.should == 1
    commands.first.last_line.should == 2
  end

  it "answers keyword? by canonical name, whatever was written" do
    one.("inc defs.rem").keyword?("INCLUDE").should.be.true
    one.("inc defs.rem").keyword?("MSG", "INCLUDE").should.be.true
    one.("inc defs.rem").keyword?("MSG").should.be.false
    one.("# note").keyword?("MSG").should.be.false
  end

  it "reports the column the keyword starts in" do
    one.("MSG hi").keyword_column.should == 1
    one.("    MSG hi").keyword_column.should == 5
  end

  it "classifies a whole file in order" do
    commands = classify.("# header\n\nSET a 1\n1 Jan MSG hi\n")

    commands.map(&:kind).should == %i[comment blank keyword implicit]
  end
end
