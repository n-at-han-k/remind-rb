# frozen_string_literal: true

require_relative "../rule"

module RemLint
  module Rules
    # Backslashes that look like line continuations and are not.
    #
    # Remind continues a line only when the backslash is the final character of
    # it (src/files.c: `if (l && (DBufValue(&buf)[l-1] == '\\'))`). One
    # invisible space after the backslash and the continuation silently stops
    # being one -- the command is cut in half, the first half usually still
    # parses as something, and the error surfaces somewhere else entirely.
    #
    # Both halves of that are worth reporting:
    #
    #   backslash then whitespace  the join you meant did not happen
    #   backslash at end of file   the command you opened never closed
    class DanglingContinuation < Rule
      SWALLOWED = /\\[ \t]+\z/

      SWALLOWED_MESSAGE =
        "Backslash followed by whitespace does not continue the line; " \
        "the backslash must be the last character"

      UNTERMINATED_MESSAGE = "File ends inside a line continuation"

      def self.default_severity
        "error"
      end

      def self.description
        "A backslash that looks like a line continuation but is not one."
      end

      def check
        check_swallowed
        check_unterminated
      end

      private

        def check_swallowed
          document.each_raw_line do |raw, line|
            body = raw.chomp
            match = body.match(SWALLOWED)

            if match
              offend(line, SWALLOWED_MESSAGE, column: match.begin(0) + 1)
            end
          end
        end

        # The joiner emits a command left open at end of file rather than
        # dropping it, precisely so this can be said out loud.
        def check_unterminated
          last = document.logical_lines.last

          if last && last.raw.chomp.end_with?("\\")
            offend(last.last_line, UNTERMINATED_MESSAGE)
          end
        end
    end
  end
end

__END__

require_relative "../document"

describe "RemLint::Rules::DanglingContinuation" do
  lint = proc do |text|
    source = RemLint::Source.new(path: "t.rem", text: text)

    RemLint::Rules::DanglingContinuation.new.run(RemLint::Document.new(source))
  end

  describe "a backslash followed by whitespace" do
    it "is reported" do
      offenses = lint.("SET x 1 + \\ \n2\n")

      offenses.length.should == 1
      offenses.first.line.should == 1
      offenses.first.message.should.match(/does not continue/)
    end

    it "points at the backslash, not at the whitespace" do
      lint.("SET x 1 + \\ \n2\n").first.column.should == 11
    end

    it "is reported for a trailing tab too" do
      lint.("SET x 1 + \\\t\n2\n").length.should == 1
    end

    it "reports at error severity" do
      lint.("SET x \\ \n").first.severity.should == "error"
    end
  end

  describe "a real continuation" do
    it "is left alone" do
      lint.("SET x 1 + \\\n    2\n").should.be.empty
    end

    it "is left alone even several lines deep" do
      lint.("SET x IIF(a, \\\n   b, \\\n   c)\n").should.be.empty
    end
  end

  describe "a file that ends inside a continuation" do
    it "is reported on the last line" do
      offenses = lint.("MSG hi\nSET x 1 + \\\n")

      offenses.map(&:message).should == ["File ends inside a line continuation"]
      offenses.first.line.should == 2
    end

    it "is reported even when the file has no trailing newline" do
      lint.("SET x 1 + \\").length.should == 1
    end

    it "reports the last physical line of a multi-line command" do
      lint.("SET x 1 + \\\n    2 + \\\n").first.line.should == 2
    end
  end

  it "says nothing about a file with no backslashes at all" do
    lint.("MSG one\nMSG two\n").should.be.empty
  end

  it "says nothing about a backslash in the middle of a line" do
    lint.(%(MSG a \\" b\n)).should.be.empty
  end
end
