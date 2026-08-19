# frozen_string_literal: true

require_relative "../rule"

module RemLint
  module Rules
    # Comparisons between literals of different types.
    #
    # `compare()` in src/expr.c settles both halves of this exactly:
    #
    #   if (v1.type != v2.type) {
    #       if (how == EQ)      ans->v.val = 0;
    #       else if (how == NE) ans->v.val = 1;
    #       else                return E_BAD_TYPE;
    #   }
    #
    # So `"foo" == 14:33` is not a comparison that happens to be false today.
    # It is the constant 0, on every date, for ever -- and Remind reports
    # nothing, because as far as it is concerned the answer is simply no. An
    # ordering operator across types at least errors, but only on the day the
    # line is reached.
    #
    # Both operands must be literals for the type to be knowable without
    # running anything, which is the usual case for the mistake: comparing a
    # variable against a constant of the wrong shape.
    class LiteralTypeMismatch < Rule
      CONSTANT = { "==" => "0", "!=" => "1" }.freeze
      ORDERING = %w[< > <= >=].freeze

      OPERATORS = (CONSTANT.keys + ORDERING).freeze

      # E_BAD_TYPE's text, from src/err.h.
      BAD_TYPE = "Type mismatch"

      # `'2027-01-01'`, `'14:33'`, `'2027-01-01@14:33'` -- src/expr.c reads a
      # single-quoted literal as a DATE, a TIME or a DATETIME by its shape.
      DATETIME = /\A'.*@.*'\z/
      DATE = %r{\A'\d{4}[-/]\d{1,2}[-/]\d{1,2}'\z}
      TIME = /\A'\d{1,2}[:.]\d{2}'\z/

      def self.default_severity
        "error"
      end

      def self.description
        "A comparison between literals of different types."
      end

      def check
        document.logical_lines.each_with_index do |logical_line, index|
          if document.commands[index].code?
            check_line(logical_line)
          end
        end
      end

      private

        def check_line(logical_line)
          tokens = document.tokens_for(logical_line)

          operators(tokens).each do |position, operator, width|
            compare(
              logical_line,
              tokens,
              position,
              operator,
              width,
            )
          end
        end

        # The lexer emits each punctuation character separately, so `<=` is two
        # tokens and `==` is two more.
        def operators(tokens)
          tokens.each_index.filter_map do |index|
            two = glyph(tokens, index, 2)
            one = glyph(tokens, index, 1)

            if OPERATORS.include?(two)
              [index, two, 2]
            elsif OPERATORS.include?(one) && !continues?(tokens, index)
              [index, one, 1]
            end
          end
        end

        def glyph(tokens, index, width)
          window = tokens[index, width]

          if window&.length == width && window.all? { |token| token.type == :other }
            window.map(&:value).join
          end
        end

        # `<` is an operator; the `<` of `<=` is half of one.
        def continues?(tokens, index)
          tokens[index + 1]&.type == :other && tokens[index + 1].value == "="
        end

        def compare(logical_line, tokens, position, operator, width)
          left = operand_before(tokens, position)
          right = operand_after(tokens, position + width)

          if left && right && left.fetch(:type) != right.fetch(:type)
            offend_at(logical_line, left.fetch(:offset), message(operator, left, right))
          end
        end

        def message(operator, left, right)
          constant = CONSTANT[operator]

          if constant
            "`#{left.fetch(:text)} #{operator} #{right.fetch(:text)}` compares " \
            "#{left.fetch(:type)} with #{right.fetch(:type)}; different types are " \
            "never equal, so this is always #{constant}"
          else
            "`#{left.fetch(:text)} #{operator} #{right.fetch(:text)}` orders " \
            "#{left.fetch(:type)} against #{right.fetch(:type)}, which Remind " \
            "rejects with `#{BAD_TYPE}`"
          end
        end

        # A literal ending at `index - 1`, provided what precedes it is a
        # boundary rather than more expression.
        def operand_before(tokens, index)
          literal = time_before(tokens, index - 1) || single(tokens, index - 1)

          if literal && boundary?(tokens[literal.fetch(:first) - 1])
            literal
          end
        end

        def operand_after(tokens, index)
          literal = time_after(tokens, index) || single(tokens, index)

          if literal && boundary?(tokens[literal.fetch(:last) + 1])
            literal
          end
        end

        # `14:33` arrives as three tokens, and is a TIME rather than two INTs.
        def time_before(tokens, index)
          time(tokens, index - 2)
        end

        def time_after(tokens, index)
          time(tokens, index)
        end

        def time(tokens, first)
          window = tokens[first, 3]

          if first >= 0 && window&.length == 3 && time_shape?(window)
            {
              type:   "TIME",
              text:   window.map(&:value).join,
              offset: window.first.offset,
              first:  first,
              last:   first + 2,
            }
          end
        end

        def time_shape?(window)
          window[0].type == :number && window[2].type == :number &&
            window[1].type == :other && [":", "."].include?(window[1].value) &&
            window[2].value.length == 2
        end

        def single(tokens, index)
          token = tokens[index]
          type = index >= 0 && token && literal_type(token)

          if type
            { type: type, text: token.value, offset: token.offset, first: index, last: index }
          end
        end

        def literal_type(token)
          case token.type
          when :number then "INT"
          when :string then quoted_type(token.value)
          end
        end

        def quoted_type(value)
          if value.start_with?('"')
            "STRING"
          else
            dated_type(value)
          end
        end

        def dated_type(value)
          if value.match?(DATETIME)
            "DATETIME"
          elsif value.match?(DATE)
            "DATE"
          elsif value.match?(TIME)
            "TIME"
          end
        end

        # An operand stands alone only if what sits beside it opens, closes,
        # separates or compares. Arithmetic is deliberately absent: in
        # `1 + 1 == "foo"` the left side of the comparison is the expression
        # `1 + 1`, not the literal `1`, and its type is not this rule's to
        # guess. The same reasoning excludes a unary minus.
        BOUNDARIES = ["&", "|", "!", "=", "<", ">"].freeze

        def boundary?(token)
          token.nil? ||
            token.type == :lbracket || token.type == :rbracket ||
            token.type == :lparen || token.type == :rparen ||
            token.type == :comma ||
            (token.type == :other && BOUNDARIES.include?(token.value))
        end
    end
  end
end

__END__

require_relative "../document"

describe "RemLint::Rules::LiteralTypeMismatch" do
  lint = proc do |text|
    source = RemLint::Source.new(path: "t.rem", text: text)

    RemLint::Rules::LiteralTypeMismatch.new.run(RemLint::Document.new(source))
  end

  messages = proc { |text| lint.(text).map(&:message) }

  describe "equality across types" do
    it "reports a STRING compared with an INT" do
      messages.(%(IF ["foo" == 14]\n)).first.should.match(
        /compares STRING with INT; different types are never equal, so this is always 0/,
      )
    end

    it "reports a STRING compared with a TIME" do
      messages.(%(IF ["foo" == 14:33]\n)).first.should.match(/compares STRING with TIME/)
    end

    it "reports != as always 1" do
      messages.(%(IF ["foo" != 14]\n)).first.should.match(/always 1/)
    end

    it "reports a DATE compared with a STRING" do
      messages.(%(IF ['2027-01-01' == "2027-01-01"]\n)).first.should.match(
        /compares DATE with STRING/,
      )
    end

    it "reports a DATETIME compared with a DATE" do
      messages.(%(IF ['2027-01-01@14:33' == '2027-01-01']\n)).first.should.match(
        /compares DATETIME with DATE/,
      )
    end
  end

  describe "ordering across types" do
    it "reports it as the error Remind raises" do
      messages.(%(IF ["foo" < 14]\n)).first.should.match(/orders STRING against INT/)
    end

    it "reports the two-character operators" do
      messages.(%(IF ["foo" <= 14]\n)).length.should == 1
      messages.(%(IF ["foo" >= 14]\n)).length.should == 1
    end
  end

  describe "comparisons that are fine" do
    it "accepts two literals of the same type" do
      lint.(%(IF ["foo" == "bar"]\n)).should.be.empty
      lint.("IF [1 == 2]\n").should.be.empty
      lint.("IF [14:33 == 15:00]\n").should.be.empty
      lint.(%(IF ['2027-01-01' == '2027-01-02']\n)).should.be.empty
    end

    it "accepts an ordering between two of the same type" do
      lint.("IF [1 < 2]\n").should.be.empty
      lint.(%(IF ["a" < "b"]\n)).should.be.empty
    end
  end

  describe "operands it cannot type" do
    it "says nothing when one side is a variable" do
      lint.(%(IF [x == "foo"]\n)).should.be.empty
      lint.(%(IF [$Tw == 5]\n)).should.be.empty
    end

    it "says nothing when one side is a call" do
      lint.(%(IF [version() == "06.02.10"]\n)).should.be.empty
    end

    it "says nothing when one side is an arithmetic expression" do
      # `1 + 1` is not a literal, so its type is not knowable here.
      lint.(%(IF [1 + 1 == "foo"]\n)).should.be.empty
    end

    it "says nothing about a single-quoted literal it cannot classify" do
      lint.(%(IF ['nonsense' == 14]\n)).should.be.empty
    end
  end

  it "checks a SATISFY expression too" do
    messages.(%(REM 13 SATISFY ["foo" == 14]\n)).length.should == 1
  end

  it "says nothing about comments" do
    lint.(%(# IF ["foo" == 14]\n)).should.be.empty
  end

  it "reports at error severity" do
    lint.(%(IF ["foo" == 14]\n)).first.severity.should == "error"
  end

  it "reports the physical line inside a continuation" do
    lint.(%(IF ["foo" \\\n    == 14]\n)).first.line.should == 1
  end
end
