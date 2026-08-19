# frozen_string_literal: true

require_relative "../rule"

module RemLint
  module Rules
    # Physical lines past a configured width.
    #
    # Off by default, and measured on physical lines rather than joined ones,
    # because the whole point of a backslash continuation is to keep a long
    # command inside the margin -- reporting the joined length would report the
    # very files that did the right thing.
    #
    # Remind has its own limit, `$MaxLineLength`, but that is a runtime guard
    # against a runaway `INCLUDECMD`, not a style setting; this is the style
    # setting.
    class LineLength < Rule
      DEFAULT_MAXIMUM = 100

      def self.enabled_by_default?
        false
      end

      def self.default_severity
        "info"
      end

      def self.description
        "Physical lines longer than Max characters."
      end

      def check
        maximum = option("Max", DEFAULT_MAXIMUM)

        document.each_raw_line do |raw, line|
          length = raw.chomp.length

          if length > maximum
            offend(line, "Line is #{length} characters, over the #{maximum} allowed", column: maximum + 1)
          end
        end
      end
    end
  end
end

__END__

require_relative "../document"

describe "RemLint::Rules::LineLength" do
  lint = proc do |text, config = {}|
    source = RemLint::Source.new(path: "t.rem", text: text)

    RemLint::Rules::LineLength.new(config).run(RemLint::Document.new(source))
  end

  short = { "Max" => 10 }

  it "is off unless the configuration asks for it" do
    RemLint::Rules::LineLength.enabled_by_default?.should.be.false
  end

  it "accepts a line at the limit" do
    lint.("MSG 123456\n", short).should.be.empty
  end

  it "reports a line over the limit" do
    offenses = lint.("MSG 1234567\n", short)

    offenses.length.should == 1
    offenses.first.message.should == "Line is 11 characters, over the 10 allowed"
  end

  it "points at the first column past the limit" do
    lint.("MSG 1234567\n", short).first.column.should == 11
  end

  it "measures physical lines, so a continuation is not penalised for the join" do
    lint.("MSG 12345\\\n    67890\n", short).should.be.empty
  end

  it "does not count the newline" do
    lint.("MSG 123456\n", short).should.be.empty
  end

  it "reports at info severity by default" do
    lint.("MSG 1234567\n", short).first.severity.should == "info"
  end

  it "defaults to a hundred characters" do
    lint.("#{'x' * 101}\n").length.should == 1
    lint.("#{'x' * 100}\n").should.be.empty
  end

  it "reports lines of a heredoc at their position in the enclosing file" do
    source = RemLint::Source.new(path: "astro", text: "MSG 1234567\n", line_offset: 12)

    RemLint::Rules::LineLength.new(short).run(RemLint::Document.new(source)).first.line.should == 13
  end
end
