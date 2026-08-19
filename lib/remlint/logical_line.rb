# frozen_string_literal: true

require_relative "source"

module RemLint
  # One Remind command, after backslash continuations have been joined.
  #
  # `text` is byte-for-byte what Remind's own LineBuffer would hold: each
  # continuing backslash replaced by a newline and the following line appended
  # verbatim (src/files.c ReadLineFromFile). Keeping the newline rather than
  # collapsing to a space costs nothing -- Remind's tokeniser treats it as
  # whitespace either way -- and buys exact column arithmetic, because every
  # character of every continued line still sits where it sat in the file.
  #
  # `line` is the physical line the command starts on, in the enclosing file;
  # `physical_lines` lists every line it spans; `raw` keeps the untouched bytes,
  # because the whitespace rules care about what the join threw away.
  LogicalLine = Struct.new(
    :text,
    :line,
    :physical_lines,
    :raw,
    keyword_init: true,
  ) do
    def continued?
      physical_lines.length > 1
    end

    def last_line
      physical_lines.last
    end

    # The command on one line, for a message or for a rule that would rather
    # not think about continuations at all.
    def squashed
      text.tr("\n", " ")
    end

    # Map a character offset in `text` back to a physical [line, column] in the
    # file. Column is 1-based, so `position_at(0)` is the first column of the
    # line the command starts on.
    def position_at(offset)
      before = text[0, offset].to_s
      crossed = before.count("\n")
      last_break = before.rindex("\n")

      if last_break
        column = offset - last_break
      else
        column = offset + 1
      end

      [physical_lines.fetch(crossed, last_line), column]
    end
  end

  # Joins backslash-continued physical lines into logical ones.
  #
  # This is where a whole bug class lives. Remind continues a line only on a
  # backslash that is the very last character; a backslash followed by a space
  # is just a backslash, and the long `IIF(...)` chains in `defs.rem` and
  # `astro` are held together by nothing else. Joining here -- rather than
  # letting each rule guess -- means every rule sees the command Remind sees,
  # and "backslash that does not continue" becomes something DanglingContinuation
  # can report rather than something that silently splits a command in half.
  module Joiner
    module_function

    def call(source)
      buffer = nil

      [].tap do |logical|
        source.lines.each_with_index do |raw, index|
          line_no = index + 1 + source.line_offset
          body = raw.chomp

          if buffer
            buffer.text << body
            buffer.physical_lines << line_no
            buffer.raw << raw
          else
            buffer = LogicalLine.new(
              text:           +body,
              line:           line_no,
              physical_lines: [line_no],
              raw:            +raw,
            )
          end

          if buffer.text.end_with?("\\")
            # Remind overwrites the backslash with the newline it just consumed.
            buffer.text[-1] = "\n"
          else
            logical << buffer
            buffer = nil
          end
        end

        # A file whose last line ends in a backslash leaves a command open.
        # Emit it anyway, so the rules can see -- and complain about -- it.
        if buffer
          logical << buffer
        end
      end
    end
  end
end

__END__

describe "line joining" do
  join = proc do |text, line_offset = 0|
    RemLint::Joiner.call(RemLint::Source.new(path: "t.rem", text: text, line_offset: line_offset))
  end

  describe "RemLint::Joiner" do
    it "leaves ordinary lines alone" do
      lines = join.("REM 1 Jan MSG New Year\nREM 2 Jan MSG Day two\n")

      lines.length.should == 2
      lines.map(&:text).should == ["REM 1 Jan MSG New Year", "REM 2 Jan MSG Day two"]
      lines.map(&:line).should == [1, 2]
    end

    it "joins a continued command the way Remind's LineBuffer does" do
      lines = join.("SET x IIF(a, \\\n   b, \\\n   c)\n")

      lines.length.should == 1
      lines.first.text.should == "SET x IIF(a, \n   b, \n   c)"
      lines.first.squashed.should == "SET x IIF(a,     b,     c)"
    end

    it "records every physical line a joined command spans" do
      line = join.("SET x 1 + \\\n2 + \\\n3\n").first

      line.line.should == 1
      line.last_line.should == 3
      line.physical_lines.should == [1, 2, 3]
      line.should.be.continued
    end

    it "keeps the raw bytes of every joined line" do
      join.("SET x 1 + \\\n  2\n").first.raw.should == "SET x 1 + \\\n  2\n"
    end

    it "does not join when the backslash is followed by whitespace" do
      # Remind continues only on a backslash in the final column. This is the
      # bug DanglingContinuation exists to report.
      lines = join.("SET x 1 + \\ \nSET y 2\n")

      lines.length.should == 2
      lines.first.text.should == "SET x 1 + \\ "
    end

    it "emits a command left open at end of file" do
      lines = join.("SET x 1 + \\\n")

      lines.length.should == 1
      lines.first.text.should == "SET x 1 + \n"
      lines.first.raw.should.match(/\\\n\z/)
    end

    it "shifts every line number by the source's offset" do
      join.("MSG one\nMSG two\n", 40).map(&:line).should == [41, 42]
    end

    it "handles an empty source" do
      join.("").should.be.empty
    end
  end

  describe "RemLint::LogicalLine#position_at" do
    it "reports a 1-based column on an unjoined line" do
      line = join.("SET x 12345\n").first

      line.position_at(0).should == [1, 1]
      line.position_at(4).should == [1, 5]
    end

    it "walks onto the physical line the offset actually landed on" do
      line = join.("SET x 1 + \\\n    22 + \\\n    333\n").first

      # The joined text is "SET x 1 + \n    22 + \n    333".
      line.position_at(line.text.index("22")).should == [2, 5]
      line.position_at(line.text.index("333")).should == [3, 5]
    end

    it "carries the source offset into reported positions" do
      line = join.("SET x 1 + \\\n    22\n", 40).first

      line.position_at(line.text.index("22")).should == [42, 5]
    end
  end
end
