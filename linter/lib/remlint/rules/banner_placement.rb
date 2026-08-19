# frozen_string_literal: true

require_relative "../rule"

module RemLint
  module Rules
    # `BANNER` written more than once, or below the reminders it appears above.
    #
    # `BANNER` sets the line Remind prints before the day's reminders, and
    # there is one of them. A second `BANNER` silently replaces the first, and
    # one written below a `REM` reads as though it applied to the reminders
    # above it when it applies to all of them equally.
    #
    # Neither is an error. The first is a line of configuration that does
    # nothing; the second is a line that does something other than where it
    # sits suggests.
    class BannerPlacement < Rule
      def self.default_severity
        "warning"
      end

      def self.description
        "A second BANNER, or a BANNER written below the first reminder."
      end

      def check
        banners = document.code_commands.select { |command| command.keyword?("BANNER") }

        report_duplicates(banners)
        report_late(banners.first)
      end

      private

        def report_duplicates(banners)
          banners.drop(1).each do |banner|
            offend(
              banner.line,
              "a second `BANNER` silently replaces the one on line #{banners.first.line}",
              column: banner.keyword_column,
            )
          end
        end

        def report_late(banner)
          first = first_reminder

          if banner && first && banner.line > first.line
            offend(
              banner.line,
              "`BANNER` applies to the whole run, so writing it below the reminder on " \
              "line #{first.line} reads as though it applied only to what follows",
              column: banner.keyword_column,
            )
          end
        end

        def first_reminder
          document.code_commands.find do |command|
            command.implicit? || command.keyword?("REM")
          end
        end
    end
  end
end

__END__

require_relative "../document"

describe "RemLint::Rules::BannerPlacement" do
  lint = proc do |text|
    source = RemLint::Source.new(path: "t.rem", text: text)

    RemLint::Rules::BannerPlacement.new.run(RemLint::Document.new(source))
  end

  messages = proc { |text| lint.(text).map(&:message) }

  it "accepts one BANNER above the reminders" do
    lint.("BANNER %\nREM 1 Jan MSG hi\n").should.be.empty
  end

  it "accepts a file with no BANNER" do
    lint.("REM 1 Jan MSG hi\n").should.be.empty
  end

  it "reports a second BANNER" do
    messages.("BANNER one\nBANNER two\n").first.should ==
      "a second `BANNER` silently replaces the one on line 1"
  end

  it "reports each BANNER after the first" do
    lint.("BANNER a\nBANNER b\nBANNER c\n").length.should == 2
  end

  it "reports a BANNER written below a reminder" do
    messages.("REM 1 Jan MSG hi\nBANNER %\n").first.should.match(
      /reads as though it applied only to what follows/,
    )
  end

  it "reports a BANNER below an implicit trigger" do
    messages.("1 Jan MSG hi\nBANNER %\n").length.should == 1
  end

  it "does not count a SET or an INCLUDE as a reminder" do
    lint.("SET a 1\nINCLUDE defs.rem\nBANNER %\n").should.be.empty
  end

  it "points at the keyword" do
    lint.("BANNER a\n   BANNER b\n").first.column.should == 4
  end

  it "says nothing about the word banner in a body" do
    lint.("REM 1 Jan MSG hang the banner\n").should.be.empty
  end

  it "says nothing about comments" do
    lint.("# BANNER a\n# BANNER b\n").should.be.empty
  end

  it "reports at warning severity" do
    lint.("BANNER a\nBANNER b\n").first.severity.should == "warning"
  end
end
