# frozen_string_literal: true

require_relative "../rule"

module RemLint
  module Rules
    # `SATISFY` inside an `IFTRIG`.
    #
    # `IFTRIG` accepts any trigger a `REM` would, with exactly one exception:
    # `SATISFY`. The exclusion is trivial to trip over, because the natural way
    # to write an `IFTRIG` is to copy a working `REM` and change the keyword --
    # and every other clause survives that edit.
    class IftrigWithSatisfy < Rule
      def self.default_severity
        "error"
      end

      def self.description
        "SATISFY inside an IFTRIG, which is the one clause IFTRIG does not take."
      end

      def check
        document.code_commands.each do |command|
          if command.keyword?("IFTRIG")
            check_iftrig(command)
          end
        end
      end

      private

        def check_iftrig(command)
          satisfy = document.trigger_for(command).body

          if satisfy&.name == "SATISFY"
            offend_at(
              command.logical_line,
              satisfy.offset,
              "`IFTRIG` takes every clause `REM` does except `SATISFY`",
            )
          end
        end
    end
  end
end

__END__

require_relative "../document"

describe "RemLint::Rules::IftrigWithSatisfy" do
  lint = proc do |text|
    source = RemLint::Source.new(path: "t.rem", text: text)

    RemLint::Rules::IftrigWithSatisfy.new.run(RemLint::Document.new(source))
  end

  it "reports SATISFY in an IFTRIG" do
    offenses = lint.("IFTRIG 13 SATISFY [$Tw == 5]\nMSG Friday the 13th\nENDIF\n")

    offenses.length.should == 1
    offenses.first.line.should == 1
    offenses.first.message.should.match(/except `SATISFY`/)
  end

  it "points at the SATISFY" do
    text = "IFTRIG 13 SATISFY [$Tw == 5]\n"

    lint.(text).first.column.should == text.index("SATISFY") + 1
  end

  it "accepts an IFTRIG with any other clause" do
    lint.("IFTRIG 1 Jan UNTIL 2027-01-01 AT 15:00\n").should.be.empty
    lint.("IFTRIG Tue SCANFROM -7\n").should.be.empty
  end

  it "accepts SATISFY on a REM, where it is legal" do
    lint.("REM 13 SATISFY [$Tw == 5] MSG Boo!\n").should.be.empty
  end

  it "matches an abbreviated IFTRIG" do
    # IFTRIG's minimum abbreviation length is 6, so IFTRIG is the short form.
    lint.("IFTRIG 13 SATISFY [1]\n").length.should == 1
  end

  it "is case-insensitive" do
    lint.("iftrig 13 satisfy [1]\n").length.should == 1
  end

  it "says nothing about the word satisfy in a comment" do
    lint.("# IFTRIG and SATISFY do not mix\n").should.be.empty
  end

  it "reports at error severity" do
    lint.("IFTRIG 13 SATISFY [1]\n").first.severity.should == "error"
  end

  it "reports the physical line inside a continuation" do
    lint.("IFTRIG 13 \\\n    SATISFY [1]\n").first.line.should == 2
  end
end
