# frozen_string_literal: true

require_relative "../rule"

module RemLint
  module Rules
    # Commands below a line reading `__EOF__`.
    #
    # Remind stops reading there and treats it as end of file
    # (src/files.c: `if (!strcmp(CurLine, "__EOF__"))`). The match is exact --
    # the whole line, no leading or trailing space -- so this is decidable by
    # looking at it.
    #
    # The marker is a debugging convenience: drop it in, and everything below
    # is temporarily switched off. The failure is leaving it in. What follows
    # still looks like live configuration, still gets edited, and never runs
    # again. Nothing in Remind's output distinguishes "this reminder did not
    # trigger today" from "Remind never read this reminder at all".
    class TextAfterEofMarker < Rule
      MARKER = "__EOF__"

      def self.default_severity
        "warning"
      end

      def self.description
        "Commands below a __EOF__ marker, which Remind never reads."
      end

      def check
        marker = marker_line

        if marker
          report(marker)
        end
      end

      private

        # The first marker wins; anything below it is unread, including a
        # second marker. `find_index` rather than an `each` with a `break`,
        # which yields the whole array when nothing matches.
        def marker_line
          document.raw_lines.find_index { |raw| raw.chomp == MARKER }
        end

        def report(index)
          live = document.commands.count do |command|
            command.code? && command.line > document.line_number_at(index)
          end

          if live.positive?
            offend(
              document.line_number_at(index),
              "`#{MARKER}` ends the file here; the #{live} command#{live == 1 ? '' : 's'} " \
              "below it are never read",
            )
          end
        end
    end
  end
end

__END__

require_relative "../document"

describe "RemLint::Rules::TextAfterEofMarker" do
  lint = proc do |text|
    source = RemLint::Source.new(path: "t.rem", text: text)

    RemLint::Rules::TextAfterEofMarker.new.run(RemLint::Document.new(source))
  end

  it "reports commands below the marker" do
    offenses = lint.("MSG live\n__EOF__\nMSG dead\n")

    offenses.length.should == 1
    offenses.first.line.should == 2
    offenses.first.message.should.match(/never read/)
  end

  it "counts how many commands are stranded" do
    lint.("__EOF__\nMSG a\nMSG b\nMSG c\n").first.message.should.match(/the 3 commands below/)
  end

  it "uses the singular for one" do
    lint.("__EOF__\nMSG a\n").first.message.should.match(/the 1 command below/)
  end

  it "says nothing when the marker is the last line" do
    lint.("MSG live\n__EOF__\n").should.be.empty
  end

  it "says nothing when only comments and blanks follow" do
    # Dead comments are not a lie about configuration.
    lint.("MSG live\n__EOF__\n# a note\n\n").should.be.empty
  end

  it "says nothing about a file with no marker" do
    lint.("MSG a\nMSG b\n").should.be.empty
  end

  describe "the match is exact" do
    it "ignores a marker with leading whitespace" do
      lint.("MSG a\n  __EOF__\nMSG b\n").should.be.empty
    end

    it "ignores a marker with trailing whitespace" do
      lint.("MSG a\n__EOF__ \nMSG b\n").should.be.empty
    end

    it "ignores a marker with anything else on the line" do
      lint.("MSG a\n__EOF__ stop here\nMSG b\n").should.be.empty
    end

    it "ignores a lower-case spelling" do
      lint.("MSG a\n__eof__\nMSG b\n").should.be.empty
    end
  end

  it "takes the first marker when there are two" do
    offenses = lint.("MSG a\n__EOF__\nMSG b\n__EOF__\nMSG c\n")

    offenses.length.should == 1
    offenses.first.line.should == 2
  end

  it "reports a heredoc's marker at its position in the enclosing file" do
    source = RemLint::Source.new(path: "astro", text: "__EOF__\nMSG a\n", line_offset: 12)

    RemLint::Rules::TextAfterEofMarker.new.run(RemLint::Document.new(source)).first.line.should == 13
  end
end
