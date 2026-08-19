# frozen_string_literal: true

require_relative "../rule"

module RemLint
  module Rules
    # Backslash escapes in a string that are not escapes.
    #
    # Remind's escape set is `\a \b \f \n \r \t \v` and `\xHH`. Anything else
    # reaches a `default:` branch in src/expr.c that emits the character and
    # drops the backslash -- so `\q` is `q`, silently, with no way to tell it
    # from a `q` somebody meant to type.
    #
    # `\\` and `\"` go through that same default branch, which is exactly how
    # they work, so neither is reported: writing them is the fix, not the
    # fault.
    #
    # `\x00` is different, and is the one case Remind refuses outright: a NUL
    # cannot appear inside a Remind string, and the parser says so.
    class StringEscape < Rule
      # From the `switch(**in)` over escapes in src/expr.c.
      DEFINED = %w[a b f n r t v x].freeze

      # Handled by the default branch, and correct.
      LITERAL = ['\\', '"', "'"].freeze

      ESCAPE = /\\(?<body>x[0-9a-fA-F]{1,2}|.)/

      NUL = /\Ax0+\z/

      def self.default_severity
        "warning"
      end

      def self.description
        "A backslash escape Remind does not define, or the prohibited \\x00."
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
          document.tokens_for(logical_line).each do |token|
            if token.type == :string && token.value.start_with?('"')
              check_string(logical_line, token)
            end
          end
        end

        def check_string(logical_line, token)
          token.value.to_enum(:scan, ESCAPE).each do
            match = Regexp.last_match
            complaint = fault(match[:body])

            if complaint
              offend_at(logical_line, token.offset + match.begin(0), complaint)
            end
          end
        end

        def fault(body)
          if body.match?(NUL)
            "`\\#{body}` is prohibited outright -- a NUL cannot appear inside a Remind string"
          elsif !DEFINED.include?(body[0]) && !LITERAL.include?(body[0])
            "`\\#{body}` is not an escape Remind defines; it drops the backslash " \
            "and prints `#{body}`"
          end
        end
    end
  end
end

__END__

require_relative "../document"

describe "RemLint::Rules::StringEscape" do
  lint = proc do |text|
    source = RemLint::Source.new(path: "t.rem", text: text)

    RemLint::Rules::StringEscape.new.run(RemLint::Document.new(source))
  end

  messages = proc { |text| lint.(text).map(&:message) }

  describe "escapes Remind defines" do
    it "accepts the control escapes" do
      lint.(%(SET a "one\\ttwo\\nthree"\n)).should.be.empty
      lint.(%(SET a "\\a\\b\\f\\r\\v"\n)).should.be.empty
    end

    it "accepts a hex escape" do
      lint.(%(SET a "\\x41\\x7f"\n)).should.be.empty
    end

    it "accepts an escaped backslash and quote" do
      # Both go through the same default branch, which is how they work.
      lint.(%(SET a "a \\\\ b \\" c"\n)).should.be.empty
    end
  end

  describe "escapes Remind does not define" do
    it "reports an unknown letter" do
      messages.(%(SET a "\\q"\n)).first.should ==
        "`\\q` is not an escape Remind defines; it drops the backslash and prints `q`"
    end

    it "reports each one" do
      messages.(%(SET a "\\q and \\z"\n)).length.should == 2
    end

    it "points at the backslash" do
      text = %(SET a "x\\qy"\n)

      lint.(text).first.column.should == text.index("\\q") + 1
    end
  end

  describe "the prohibited NUL" do
    it "reports \\x00" do
      messages.(%(SET a "\\x00"\n)).first.should.match(/prohibited outright/)
    end

    it "reports \\x0 as well" do
      messages.(%(SET a "\\x0"\n)).first.should.match(/prohibited outright/)
    end

    it "accepts a hex escape that is not zero" do
      lint.(%(SET a "\\x01"\n)).should.be.empty
    end
  end

  describe "where it does not look" do
    it "says nothing about a single-quoted date constant" do
      lint.("SET a '2027-01-01'\n").should.be.empty
    end

    it "says nothing about a backslash outside a string" do
      # A trailing backslash is a line continuation, not an escape.
      lint.("SET a 1 + \\\n    2\n").should.be.empty
    end

    it "says nothing about comments" do
      lint.(%(# SET a "\\q"\n)).should.be.empty
    end
  end

  it "reports at warning severity" do
    lint.(%(SET a "\\q"\n)).first.severity.should == "warning"
  end
end
