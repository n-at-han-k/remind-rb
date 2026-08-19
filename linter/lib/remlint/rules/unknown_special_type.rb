# frozen_string_literal: true

require_relative "../rule"

module RemLint
  module Rules
    # `SPECIAL` types no shipped back-end understands.
    #
    # Remind passes a `SPECIAL` through untouched and the back-end is required
    # to ignore anything it cannot parse. That contract is what makes `SPECIAL`
    # extensible, and it is also why a typo is invisible: `SPECIAL SHDE 255 255
    # 204` produces no error, no warning and no shading. The reminder triggers,
    # the back-end shrugs, and the day is simply not coloured in.
    #
    # The shipped set is what the back-ends actually test `passthru` against --
    # including `PostScript` and `PSFile`, which rem2ps reads and which are
    # easy to forget because they look like reminder types rather than SPECIAL
    # ones. A project with its own back-end adds to the set with
    # `AllowedTypes`, which is the whole point of the passthrough.
    class UnknownSpecialType < Rule
      # Every value the shipped back-ends compare `passthru` against: the
      # calendar ones from src/calendar.c and src/rem2ps.c, and the HTML and
      # Pango ones from rem2html and Remind::PDF.
      KNOWN = %w[
        SHADE MOON WEEK COLOR COLOUR
        POSTSCRIPT PSFILE PS
        PANGO HTML HTMLCLASS
      ].freeze

      def self.default_severity
        "warning"
      end

      def self.description
        "A SPECIAL type no shipped back-end parses."
      end

      def check
        allowed = KNOWN + option("AllowedTypes", []).map(&:upcase)

        document.code_commands.each do |command|
          check_special(command, allowed)
        end
      end

      private

        def check_special(command, allowed)
          trigger = document.trigger_for(command)

          if trigger.body&.name == "SPECIAL"
            report(command, trigger, allowed)
          end
        end

        def report(command, trigger, allowed)
          tokens = document.tokens_for(command.logical_line)
          token = tokens[trigger.body.argument_index]

          if token&.type == :name && !allowed.include?(token.value.upcase)
            offend_at(command.logical_line, token.offset, message(token, allowed))
          end
        end

        def message(token, allowed)
          "`SPECIAL #{token.value}` is a type no shipped back-end parses, so it " \
          "produces no output and no error; the shipped set is #{allowed.join(', ')}"
        end
    end
  end
end

__END__

require_relative "../document"

describe "RemLint::Rules::UnknownSpecialType" do
  lint = proc do |text, config = {}|
    source = RemLint::Source.new(path: "t.rem", text: text)

    RemLint::Rules::UnknownSpecialType.new(config).run(RemLint::Document.new(source))
  end

  messages = proc { |text, config = {}| lint.(text, config).map(&:message) }

  describe "types the back-ends parse" do
    it "accepts SHADE and MOON" do
      lint.("REM Mon SPECIAL SHADE 255 255 204\n").should.be.empty
      lint.("REM Mon SPECIAL MOON 0\n").should.be.empty
    end

    it "accepts COLOR and its other spelling" do
      lint.("REM Mon SPECIAL COLOR 255 0 0 Sunset\n").should.be.empty
      lint.("REM Mon SPECIAL COLOUR 255 0 0 Sunset\n").should.be.empty
    end

    it "accepts the PostScript passthroughs rem2ps reads" do
      # tests/test2.rem writes this one, and rem2ps.c compares against it.
      lint.("REM 21 AUG AT 1:55 SPECIAL PostScript (wookie) show\n").should.be.empty
      lint.("REM Mon SPECIAL PSFile /tmp/x.ps\n").should.be.empty
    end

    it "accepts WEEK, PANGO and HTML" do
      lint.("REM Mon SPECIAL WEEK 5\n").should.be.empty
      lint.("REM Mon SPECIAL PANGO <b>bold</b>\n").should.be.empty
      lint.("REM Mon SPECIAL HTML <b>bold</b>\n").should.be.empty
    end

    it "is case-insensitive" do
      lint.("REM Mon SPECIAL shade 255 255 204\n").should.be.empty
    end
  end

  describe "types nothing parses" do
    it "reports a typo" do
      messages.("REM Mon SPECIAL SHDE 255 255 204\n").first.should.match(
        /`SPECIAL SHDE` is a type no shipped back-end parses/,
      )
    end

    it "explains the silence" do
      messages.("REM Mon SPECIAL SHDE 1\n").first.should.match(
        /produces no output and no error/,
      )
    end

    it "points at the type" do
      text = "REM Mon SPECIAL SHDE 1\n"

      lint.(text).first.column.should == text.index("SHDE") + 1
    end
  end

  describe "AllowedTypes" do
    it "accepts a type the configuration adds" do
      lint.("REM Mon SPECIAL MYTHING 1\n", "AllowedTypes" => ["MYTHING"]).should.be.empty
    end

    it "matches an added type case-insensitively" do
      lint.("REM Mon SPECIAL mything 1\n", "AllowedTypes" => ["MyThing"]).should.be.empty
    end
  end

  it "says nothing about a reminder that is not a SPECIAL" do
    lint.("REM Mon MSG SPECIAL SHDE\n").should.be.empty
  end

  it "says nothing about comments" do
    lint.("# REM Mon SPECIAL SHDE 1\n").should.be.empty
  end

  it "reports at warning severity" do
    lint.("REM Mon SPECIAL SHDE 1\n").first.severity.should == "warning"
  end
end
