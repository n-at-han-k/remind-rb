# frozen_string_literal: true

require_relative "../rule"

module RemLint
  module Rules
    # Whitespace at the end of a line.
    #
    # Not bikeshedding in Remind. The shipped `examples/remind.vim` highlights
    # it as an *error*, with the note "This will match trailing whitespaces
    # that seem to break rem2ps". A linter that stayed quiet about it would
    # disagree with the editor Remind ships.
    #
    # The pattern is vim's -- `\S\s\+$`, a non-space then whitespace -- so a
    # line of nothing but spaces is left alone. Emptying such a line is a
    # cosmetic change and flagging every one of them in a file that has a few
    # is how a linter teaches people to ignore it.
    #
    # A trailing run that follows a backslash belongs to DanglingContinuation,
    # which has something more useful to say about it, so it is skipped here
    # rather than reported twice.
    class TrailingWhitespace < Rule
      OFFENDING = /\S[ \t]+\z/
      AFTER_CONTINUATION = /\\[ \t]+\z/

      MESSAGE = "Trailing whitespace (breaks rem2ps output)"

      def self.default_severity
        "error"
      end

      def self.description
        "Whitespace at the end of a line, which breaks rem2ps output."
      end

      def check
        document.each_raw_line do |raw, line|
          body = raw.chomp

          if offending?(body)
            offend(line, MESSAGE, column: body.rstrip.length + 1)
          end
        end
      end

      private

        def offending?(body)
          body.match?(OFFENDING) && !body.match?(AFTER_CONTINUATION)
        end
    end
  end
end

__END__

require_relative "../document"

describe "RemLint::Rules::TrailingWhitespace" do
  lint = proc do |text, config = {}|
    source = RemLint::Source.new(path: "t.rem", text: text)

    RemLint::Rules::TrailingWhitespace.new(config).run(RemLint::Document.new(source))
  end

  it "flags a line that ends in a space" do
    offenses = lint.("MSG hello \n")

    offenses.length.should == 1
    offenses.first.line.should == 1
    offenses.first.message.should.match(/rem2ps/)
  end

  it "points at the first character of the trailing run" do
    lint.("MSG hello   \n").first.column.should == 10
  end

  it "flags a trailing tab" do
    lint.("MSG hello\t\n").length.should == 1
  end

  it "reports at error severity, as remind.vim does" do
    lint.("MSG hello \n").first.severity.should == "error"
  end

  it "says nothing about a clean file" do
    lint.("MSG hello\nMSG again\n").should.be.empty
  end

  it "says nothing about a line of nothing but whitespace" do
    # remind.vim's pattern needs a non-space before the run, and so does this.
    lint.("MSG hi\n   \nMSG bye\n").should.be.empty
  end

  it "leaves a dangling continuation to the rule that explains it" do
    lint.("SET x 1 + \\ \n").should.be.empty
  end

  it "still flags a line whose backslash is not at the end" do
    lint.("MSG a \\ b \n").length.should == 1
  end

  it "flags every offending line in a file" do
    lint.("MSG a \nMSG b\nMSG c\t\n").map(&:line).should == [1, 3]
  end

  it "reports lines of a heredoc at their position in the enclosing file" do
    source = RemLint::Source.new(path: "astro", text: "MSG a \n", line_offset: 40)

    RemLint::Rules::TrailingWhitespace.new.run(RemLint::Document.new(source)).first.line.should == 41
  end

  it "takes its severity from configuration" do
    lint.("MSG a \n", "Severity" => "warning").first.severity.should == "warning"
  end
end
