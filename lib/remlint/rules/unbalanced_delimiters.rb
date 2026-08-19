# frozen_string_literal: true

require_relative "../rule"

module RemLint
  module Rules
    # Brackets and parentheses that never close, or that close each other.
    #
    # Remind has `Missing ']'` and `Missing ')'` (src/err.h E_MISS_END,
    # E_MISS_RIGHT_PAREN), so this reports something Remind agrees is wrong --
    # it just reports it without running the file, and names the line the
    # delimiter opened on rather than the line parsing gave up at.
    #
    # Two asymmetries matter, and both come from Remind treating unbracketed
    # text as text:
    #
    # A CLOSER WITH NOTHING OPEN IS NOT AN ERROR. `MSG See note ]` prints a
    # bracket. Reporting it would make the rule unusable on message bodies,
    # which is most of what a reminder file is.
    #
    # PARENTHESES ONLY COUNT INSIDE AN EXPRESSION. `MSG Call (555) 1234` is
    # text, not a call with a missing operand. So parentheses are tracked
    # inside `[...]`, and in the arguments of the commands whose arguments are
    # expressions -- `IF`, `SET`, `FSET` and friends -- and nowhere else.
    #
    # String literals are skipped, because the lexer already took them whole:
    # the `]` in `MSG a "]" b` is inside a string and closes nothing.
    class UnbalancedDelimiters < Rule
      # Commands whose arguments Remind evaluates as an expression, so that
      # parentheses in them are syntax rather than punctuation.
      EXPRESSION_COMMANDS = %w[
        IF IFTRIG SET FSET OMITFUNC EXPR MAX-OVERDUE
      ].freeze

      CLOSER_FOR = { lbracket: :rbracket, lparen: :rparen }.freeze
      GLYPH = { lbracket: "[", rbracket: "]", lparen: "(", rparen: ")" }.freeze

      def self.default_severity
        "error"
      end

      def self.description
        "Brackets and parentheses that are never closed, or that close each other."
      end

      def check
        document.logical_lines.each_with_index do |logical_line, index|
          command = document.commands[index]

          if command.code?
            check_line(logical_line, command)
          end
        end
      end

      private

        def check_line(logical_line, command)
          stack = []
          expression = expression_command?(command)

          document.tokens_for(logical_line).each do |token|
            step(
              stack,
              token,
              logical_line,
              expression,
            )
          end

          report_unclosed(stack, logical_line)
        end

        def step(stack, token, logical_line, expression)
          if opener?(token, stack, expression)
            stack.push(token)
          elsif closer?(token, stack, expression)
            match(stack, token, logical_line)
          end
        end

        def opener?(token, stack, expression)
          token.type == :lbracket ||
            (token.type == :lparen && parens_count?(stack, expression))
        end

        def closer?(token, stack, expression)
          token.type == :rbracket ||
            (token.type == :rparen && parens_count?(stack, expression))
        end

        # Inside a bracketed expression, or in the arguments of a command whose
        # arguments are one.
        def parens_count?(stack, expression)
          expression || stack.any? { |open| open.type == :lbracket }
        end

        def match(stack, token, logical_line)
          top = stack.last

          if top.nil?
            nil # A closer with nothing open is literal text, not an error.
          elsif CLOSER_FOR.fetch(top.type) == token.type
            stack.pop
          else
            report_crossed(stack, token, logical_line)
          end
        end

        def report_crossed(stack, token, logical_line)
          top = stack.pop
          line, _column = logical_line.position_at(top.offset)

          offend_at(
            logical_line,
            token.offset,
            "`#{GLYPH.fetch(token.type)}` closes `#{GLYPH.fetch(top.type)}` opened " \
            "on line #{line}",
          )
        end

        def report_unclosed(stack, logical_line)
          stack.each do |token|
            offend_at(
              logical_line,
              token.offset,
              "`#{GLYPH.fetch(token.type)}` is never closed by " \
              "`#{GLYPH.fetch(CLOSER_FOR.fetch(token.type))}`",
            )
          end
        end

        def expression_command?(command)
          command.keyword?(*EXPRESSION_COMMANDS)
        end
    end
  end
end

__END__

require_relative "../document"

describe "RemLint::Rules::UnbalancedDelimiters" do
  lint = proc do |text|
    source = RemLint::Source.new(path: "t.rem", text: text)

    RemLint::Rules::UnbalancedDelimiters.new.run(RemLint::Document.new(source))
  end

  messages = proc { |text| lint.(text).map(&:message) }

  describe "balanced code" do
    it "accepts a bracketed substitution" do
      lint.("MSG This is [center(\"hello\")]\n").should.be.empty
    end

    it "accepts the nested calls alignment.rem uses" do
      lint.("MSG [ansicolor(255,255,0) + center(\"x \") + ansicolor(\"\")]\n").should.be.empty
    end

    it "accepts an expression command with parentheses and no brackets" do
      lint.("IF version() < \"03.04.02\"\n").should.be.empty
      lint.("FSET center(x) pad(\"\", \" \", (columns() - columns(x))/2) + x\n").should.be.empty
    end

    it "accepts a system-include path" do
      lint.("INCLUDE [$SysInclude]/ansitext.rem\n").should.be.empty
    end

    it "accepts brackets spread over a continuation" do
      lint.("SET x [IIF(a, \\\n   b, \\\n   c)]\n").should.be.empty
    end
  end

  describe "text that only looks unbalanced" do
    it "leaves a closer with nothing open alone" do
      lint.("MSG See note ]\n").should.be.empty
      lint.("MSG Call me )\n").should.be.empty
    end

    it "leaves parentheses in a message body alone" do
      lint.("MSG Call (555 1234 tomorrow\n").should.be.empty
    end

    it "leaves parentheses in a RUN body alone" do
      lint.("RUN echo $(date\n").should.be.empty
    end

    it "does not count a bracket inside a string literal" do
      lint.(%(MSG a "]" b\n)).should.be.empty
      lint.(%(MSG a "[" b\n)).should.be.empty
    end
  end

  describe "an unclosed bracket" do
    it "is reported" do
      messages.("MSG value is [x\n").should == ["`[` is never closed by `]`"]
    end

    it "points at the bracket" do
      lint.("MSG value is [x\n").first.column.should == 14
    end

    it "is reported once per unclosed bracket" do
      messages.("MSG [a [b\n").length.should == 2
    end

    it "is reported on the physical line it opened on" do
      lint.("SET x 1 + \\\n    [y\n").first.line.should == 2
    end
  end

  describe "an unclosed parenthesis" do
    it "is reported inside a bracketed expression" do
      messages.("MSG [center(\"x\"\n").should ==
        ["`[` is never closed by `]`", "`(` is never closed by `)`"]
    end

    it "is reported in an expression command" do
      messages.("IF trigger(x\n").should == ["`(` is never closed by `)`"]
    end
  end

  describe "delimiters that cross" do
    it "reports a bracket closed by a parenthesis" do
      messages.("SET x (a]\n").should == ["`]` closes `(` opened on line 1"]
    end

    it "reports a parenthesis closed by a bracket" do
      # The `]` crosses the `(`, and the `[` it was meant to close is then
      # left open -- both halves of the mistake get said.
      messages.("MSG [foo(]\n").should ==
        ["`]` closes `(` opened on line 1", "`[` is never closed by `]`"]
    end
  end

  it "reports at error severity" do
    lint.("MSG [x\n").first.severity.should == "error"
  end

  it "says nothing about comments" do
    lint.("# a note with [ and (\n").should.be.empty
  end

  it "reports lines of a heredoc at their position in the enclosing file" do
    source = RemLint::Source.new(path: "astro", text: "MSG [x\n", line_offset: 12)

    RemLint::Rules::UnbalancedDelimiters.new.run(RemLint::Document.new(source)).first.line.should == 13
  end
end
