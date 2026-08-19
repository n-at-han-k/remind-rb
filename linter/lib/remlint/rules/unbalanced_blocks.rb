# frozen_string_literal: true

require_relative "../rule"

module RemLint
  module Rules
    # Block commands that never close, close the wrong thing, or close nothing.
    #
    # Remind has its own "Warning: Missing ENDIF" (src/err.h E_MISS_ENDIF), but
    # only for the file it actually reaches the end of, and only once it has
    # run everything above. A linter can say it before anything runs, name the
    # line the block opened on, and cover the three context stacks Remind's own
    # warning does not:
    #
    #   IF / IFTRIG ... ELSE ... ENDIF
    #   PUSH-OMIT-CONTEXT ... POP-OMIT-CONTEXT
    #   PUSH-VARS ... POP-VARS
    #   PUSH-FUNCS ... POP-FUNCS
    #
    # `defs.rem` nests IF inside ELSE inside IF for its Yom Hazikaron
    # calculation and brackets its US Tax Day block in PUSH/POP-OMIT-CONTEXT,
    # so all of this is load-bearing in the shipped examples.
    #
    # Matching is by canonical keyword, so the abbreviations Remind allows --
    # `PUSH` for PUSH-OMIT-CONTEXT, `POP` for POP-OMIT-CONTEXT -- are matched
    # like the long forms rather than missed.
    class UnbalancedBlocks < Rule
      PAIRS = {
        "IF"                => "ENDIF",
        "IFTRIG"            => "ENDIF",
        "PUSH-OMIT-CONTEXT" => "POP-OMIT-CONTEXT",
        "PUSH-VARS"         => "POP-VARS",
        "PUSH-FUNCS"        => "POP-FUNCS",
      }.freeze

      CLOSERS = PAIRS.values.uniq.freeze

      # `IF_NEST` in src/ifelse.c. The 65th level is an error rather than a
      # deeper nesting, and the linter can say so before the file runs -- though
      # a script at that depth has larger problems than this rule.
      MAX_IF_DEPTH = 64

      # Which openers a given closer is allowed to close.
      OPENERS_FOR = CLOSERS.to_h do |closer|
        [closer, PAIRS.select { |_opener, close| close == closer }.keys]
      end.freeze

      def self.default_severity
        "error"
      end

      def self.description
        "IF/ENDIF, ELSE and the PUSH/POP context commands that do not pair up."
      end

      def check
        @stack = []

        document.code_commands.each do |command|
          dispatch(command)
        end

        report_unclosed
      end

      private

        def dispatch(command)
          if PAIRS.key?(keyword_of(command))
            @stack.push({ command: command, else_line: nil })
            check_depth(command)
          elsif CLOSERS.include?(keyword_of(command))
            close(command)
          elsif command.keyword?("ELSE")
            handle_else(command)
          end
        end

        def keyword_of(command)
          command.keyword&.name
        end

        def check_depth(command)
          depth = @stack.count { |frame| conditional?(frame) }

          if depth == MAX_IF_DEPTH + 1 && conditional?(@stack.last)
            offend(
              command.line,
              "`IF` blocks nest #{MAX_IF_DEPTH} deep at most; this is level #{depth}",
              column: command.keyword_column,
            )
          end
        end

        def close(command)
          closer = keyword_of(command)
          frame = @stack.last

          if frame.nil? || !OPENERS_FOR.fetch(closer).include?(keyword_of(frame[:command]))
            report_stray(command, closer, frame)
          else
            @stack.pop
          end
        end

        # A closer that matches nothing on the stack is one of two different
        # mistakes, and the message says which: nothing is open at all, or
        # something else is open and this closer crosses it.
        def report_stray(command, closer, frame)
          if frame.nil?
            offend(
              command.line,
              "`#{closer}` with nothing open to close",
              column: command.keyword_column,
            )
          else
            opener = frame[:command]

            offend(
              command.line,
              "`#{closer}` closes `#{keyword_of(opener)}` opened on line #{opener.line}",
              column: command.keyword_column,
            )
          end
        end

        def handle_else(command)
          frame = @stack.reverse.find { |candidate| conditional?(candidate) }

          if frame.nil?
            offend(command.line, "`ELSE` outside any `IF` block", column: command.keyword_column)
          elsif frame[:else_line]
            offend(
              command.line,
              "`ELSE` already given for this `IF` on line #{frame[:else_line]}",
              column: command.keyword_column,
            )
          else
            frame[:else_line] = command.line
          end
        end

        def conditional?(frame)
          PAIRS[keyword_of(frame[:command])] == "ENDIF"
        end

        def report_unclosed
          @stack.each do |frame|
            opener = frame[:command]
            keyword = keyword_of(opener)

            offend(
              opener.line,
              "`#{keyword}` is never closed by `#{PAIRS.fetch(keyword)}`",
              column: opener.keyword_column,
            )
          end
        end
    end
  end
end

__END__

require_relative "../document"

describe "RemLint::Rules::UnbalancedBlocks" do
  lint = proc do |text|
    source = RemLint::Source.new(path: "t.rem", text: text)

    RemLint::Rules::UnbalancedBlocks.new.run(RemLint::Document.new(source))
  end

  messages = proc { |text| lint.(text).map(&:message) }

  describe "balanced code" do
    it "accepts a simple conditional" do
      lint.("IF a\n   MSG yes\nENDIF\n").should.be.empty
    end

    it "accepts an ELSE" do
      lint.("IF a\n   MSG yes\nELSE\n   MSG no\nENDIF\n").should.be.empty
    end

    it "accepts nesting, as defs.rem does" do
      lint.("IF a\nIF b\nMSG x\nELSE\nMSG y\nENDIF\nELSE\nMSG z\nENDIF\n").should.be.empty
    end

    it "accepts IFTRIG" do
      lint.("IFTRIG 1 Jan\n   MSG hi\nENDIF\n").should.be.empty
    end

    it "accepts the omit-context stack" do
      lint.("PUSH-OMIT-CONTEXT\nOMIT 1 Jan\nPOP-OMIT-CONTEXT\n").should.be.empty
    end

    it "accepts the abbreviations Remind allows for it" do
      lint.("PUSH\nOMIT 1 Jan\nPOP\n").should.be.empty
    end

    it "accepts the vars and funcs stacks" do
      lint.("PUSH-VARS\nSET a 1\nPOP-VARS\n").should.be.empty
      lint.("PUSH-FUNCS\nFSET f(x) x\nPOP-FUNCS\n").should.be.empty
    end

    it "is not confused by a comment or a blank line inside a block" do
      lint.("IF a\n\n# note\nMSG x\nENDIF\n").should.be.empty
    end
  end

  describe "an unclosed opener" do
    it "is reported on the line it opened" do
      offenses = lint.("IF $TerminalBackground == 0\n   MSG dark\n")

      offenses.length.should == 1
      offenses.first.line.should == 1
      offenses.first.message.should.match(/never closed by `ENDIF`/)
    end

    it "is reported for each of several" do
      messages.("IF a\nIF b\nMSG x\n").length.should == 2
    end

    it "names the right closer for a context stack" do
      messages.("PUSH-VARS\nSET a 1\n").first.should.match(/never closed by `POP-VARS`/)
    end

    it "points at the keyword's column" do
      lint.("   IF a\n").first.column.should == 4
    end
  end

  describe "a closer with nothing open" do
    it "is reported" do
      messages.("MSG hi\nENDIF\n").should == ["`ENDIF` with nothing open to close"]
    end

    it "is reported for a stray POP too" do
      messages.("POP-OMIT-CONTEXT\n").first.should.match(/nothing open/)
    end
  end

  describe "a closer that crosses another block" do
    it "names the block it crossed and where that opened" do
      messages.("IF a\nPOP-OMIT-CONTEXT\nENDIF\n").first.should ==
        "`POP-OMIT-CONTEXT` closes `IF` opened on line 1"
    end
  end

  describe "ELSE" do
    it "outside any IF is reported" do
      messages.("MSG hi\nELSE\nMSG bye\n").should == ["`ELSE` outside any `IF` block"]
    end

    it "inside an omit-context block but no IF is reported" do
      messages.("PUSH-OMIT-CONTEXT\nELSE\nPOP-OMIT-CONTEXT\n").should ==
        ["`ELSE` outside any `IF` block"]
    end

    it "given twice for one IF is reported the second time" do
      offenses = lint.("IF a\nMSG x\nELSE\nMSG y\nELSE\nMSG z\nENDIF\n")

      offenses.length.should == 1
      offenses.first.line.should == 5
      offenses.first.message.should.match(/already given/)
    end

    it "is allowed once in each of two nested IFs" do
      lint.("IF a\nIF b\nMSG x\nELSE\nMSG y\nENDIF\nELSE\nMSG z\nENDIF\n").should.be.empty
    end
  end

  describe "nesting depth" do
    it "accepts 64 levels" do
      text = ("IF a\n" * 64) + "MSG hi\n" + ("ENDIF\n" * 64)

      lint.(text).should.be.empty
    end

    it "reports the 65th" do
      text = ("IF a\n" * 65) + "MSG hi\n" + ("ENDIF\n" * 65)
      offenses = lint.(text)

      offenses.length.should == 1
      offenses.first.line.should == 65
      offenses.first.message.should.match(/nest 64 deep at most; this is level 65/)
    end

    it "does not count the context stacks toward the IF limit" do
      text = ("PUSH-OMIT-CONTEXT\n" * 70) + ("POP-OMIT-CONTEXT\n" * 70)

      lint.(text).should.be.empty
    end
  end

  it "reports at error severity" do
    lint.("IF a\n").first.severity.should == "error"
  end

  it "reports lines of a heredoc at their position in the enclosing file" do
    source = RemLint::Source.new(path: "astro", text: "IF a\nMSG x\n", line_offset: 12)

    RemLint::Rules::UnbalancedBlocks.new.run(RemLint::Document.new(source)).first.line.should == 13
  end
end
