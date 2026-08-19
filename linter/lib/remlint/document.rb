# frozen_string_literal: true

require_relative "source"
require_relative "logical_line"
require_relative "command"
require_relative "expr_lexer"
require_relative "trigger"

module RemLint
  # Everything a rule may look at, built once per source and shared by all of
  # them.
  #
  # The four views answer four different questions and rules should take the
  # narrowest one that works:
  #
  #   raw_lines      the bytes, per physical line -- for whitespace rules
  #   logical_lines  continuations joined -- for anything spanning lines
  #   commands       classified -- for anything keyed on which command it is
  #   tokens_for     lexed -- for anything looking inside a command
  #   trigger_for    clauses located -- for anything keyed on AT, UNTIL, TZ ...
  #
  # Building all of it eagerly except the token streams keeps rules cheap
  # without lexing files no rule looks inside; the token streams are memoised
  # per logical line, so several rules asking cost one lex.
  class Document
    attr_reader :source, :logical_lines, :commands

    def initialize(source)
      @source = source
      @logical_lines = Joiner.call(source)
      @commands = Classifier.all(@logical_lines)
      @token_cache = {}
      @trigger_cache = {}
    end

    def path
      source.path
    end

    def line_offset
      source.line_offset
    end

    def label
      source.label
    end

    # The physical lines, exactly as they are in the file, newline and all.
    def raw_lines
      @raw_lines ||= source.lines
    end

    # The file line number of `raw_lines[index]`.
    def line_number_at(index)
      index + 1 + line_offset
    end

    def each_raw_line
      raw_lines.each_with_index do |raw, index|
        yield raw, line_number_at(index)
      end
    end

    # Significant tokens of one logical line, lexed at most once.
    def tokens_for(logical_line)
      @token_cache[logical_line.line] ||= ExprLexer.significant(logical_line.text)
    end

    # The clauses of one command's trigger, parsed at most once. Rules ask this
    # rather than scanning tokens themselves, because the trigger/body boundary
    # is easy to get wrong and expensive to get wrong twice.
    def trigger_for(command)
      @trigger_cache[command.line] ||= Trigger.of(
        tokens_for(command.logical_line),
        triggered: Trigger.triggered?(command),
      )
    end

    def code_commands
      @code_commands ||= commands.select(&:code?)
    end
  end
end

__END__

describe "RemLint::Document" do
  document = proc do |text, line_offset = 0|
    RemLint::Document.new(RemLint::Source.new(path: "t.rem", text: text, line_offset: line_offset))
  end

  sample = "# header\nIF a\n   MSG [x] \\\n       [y]\nENDIF\n"

  it "exposes the physical lines untouched" do
    document.(sample).raw_lines.length.should == 5
    document.(sample).raw_lines.first.should == "# header\n"
  end

  it "exposes logical lines with continuations joined" do
    document.(sample).logical_lines.length.should == 4
  end

  it "exposes classified commands" do
    document.(sample).commands.map(&:kind).should == %i[comment keyword keyword keyword]
  end

  it "filters out comments and blanks for rules that only want code" do
    document.("# note\n\nMSG hi\n").code_commands.map(&:line).should == [3]
  end

  it "numbers physical lines through the source offset" do
    doc = document.("MSG one\nMSG two\n", 40)

    doc.line_number_at(0).should == 41
    doc.logical_lines.map(&:line).should == [41, 42]
  end

  it "yields each raw line with its file line number" do
    seen = []
    document.("MSG one\nMSG two\n", 40).each_raw_line { |raw, line| seen << [raw.chomp, line] }

    seen.should == [["MSG one", 41], ["MSG two", 42]]
  end

  it "lexes a logical line once and reuses the result" do
    doc = document.("MSG [ansicolor(1,2,3)]\n")
    line = doc.logical_lines.first

    doc.tokens_for(line).map(&:type).should.include :function
    doc.tokens_for(line).should.be.identical_to doc.tokens_for(line)
  end

  it "parses a command's trigger once and reuses the result" do
    doc = document.("REM Tue AT 15:00 MSG Meet Bob at the pub\n")
    command = doc.code_commands.first

    doc.trigger_for(command).include?("AT").should.be.true
    doc.trigger_for(command).should.be.identical_to doc.trigger_for(command)
  end

  it "carries the source's label for messages" do
    source = RemLint::Source.new(path: "astro", text: "MSG hi\n", description: "heredoc at line 3")

    RemLint::Document.new(source).label.should == "astro (heredoc at line 3)"
  end
end
