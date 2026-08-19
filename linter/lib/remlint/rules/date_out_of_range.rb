# frozen_string_literal: true

require_relative "../rule"
require_relative "../date_literal"

module RemLint
  module Rules
    # Dates outside the range Remind can represent.
    #
    # Remind counts days from `BASE`, which is 1990, and represents
    # `YR_RANGE` years, which is 4000 (src/custom.h.in). So 1990-01-01 to
    # 5990-12-31 is not a policy, it is the type. A date below the floor cannot
    # be stored at all.
    #
    # Three of the book's rules asked for a slice of this each --
    # `TriggerComponentRange`, `DateConstantBeforeEpoch`,
    # `DateOutsideRepresentableRange` -- and Appendix B's own note suggested
    # collecting them. One rule keeps the message identical wherever the date
    # was written.
    #
    # Two shapes are checked: a spelled-out date in a trigger, and a
    # single-quoted date constant in an expression. A day of 32 or a month
    # nobody has is caught by the same walk.
    class DateOutOfRange < Rule
      FIRST_YEAR = DateLiteral::EPOCH_YEAR
      LAST_YEAR = DateLiteral::LAST_YEAR

      # `'1970-01-01'`, `'2027-13-01'` -- a date constant, which the lexer
      # hands over whole.
      CONSTANT = %r{\A'(?<year>\d{4})[-/](?<month>\d{1,2})[-/](?<day>\d{1,2})}

      DAYS_IN_MONTH = [31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31].freeze

      def self.default_severity
        "error"
      end

      def self.description
        "A date outside 1990-01-01 to 5990-12-31, or with an impossible component."
      end

      def check
        document.logical_lines.each_with_index do |logical_line, index|
          if document.commands[index].code?
            check_constants(logical_line)
          end
        end
      end

      private

        def check_constants(logical_line)
          document.tokens_for(logical_line).each do |token|
            match = token.type == :string && token.value.match(CONSTANT)

            if match
              report(logical_line, token, match)
            end
          end
        end

        def report(logical_line, token, match)
          year = match[:year].to_i
          month = match[:month].to_i
          day = match[:day].to_i
          complaint = fault(year, month, day)

          if complaint
            offend_at(logical_line, token.offset, "`#{token.value}` #{complaint}")
          end
        end

        def fault(year, month, day)
          if year < FIRST_YEAR
            "is before #{FIRST_YEAR}-01-01, which is the earliest date Remind represents"
          elsif year > LAST_YEAR
            "is after #{LAST_YEAR}-12-31, which is the latest date Remind represents"
          else
            component_fault(month, day)
          end
        end

        def component_fault(month, day)
          if month < 1 || month > 12
            "has month #{month}"
          elsif day < 1 || day > DAYS_IN_MONTH[month - 1]
            "has day #{day} in a month with #{DAYS_IN_MONTH[month - 1]}"
          end
        end
    end
  end
end

__END__

require_relative "../document"

describe "RemLint::Rules::DateOutOfRange" do
  lint = proc do |text|
    source = RemLint::Source.new(path: "t.rem", text: text)

    RemLint::Rules::DateOutOfRange.new.run(RemLint::Document.new(source))
  end

  messages = proc { |text| lint.(text).map(&:message) }

  describe "dates Remind cannot represent" do
    it "reports one before the epoch" do
      messages.("SET a '1970-01-01'\n").first.should ==
        "`'1970-01-01'` is before 1990-01-01, which is the earliest date Remind represents"
    end

    it "reports one after the last year" do
      messages.("SET a '9999-01-01'\n").first.should.match(/is after 5990-12-31/)
    end

    it "accepts the first representable date" do
      lint.("SET a '1990-01-01'\n").should.be.empty
    end

    it "accepts the last representable year" do
      lint.("SET a '5990-12-31'\n").should.be.empty
    end
  end

  describe "impossible components" do
    it "reports a month of 13" do
      messages.("SET a '2027-13-01'\n").first.should.match(/has month 13/)
    end

    it "reports a month of 0" do
      messages.("SET a '2027-00-01'\n").first.should.match(/has month 0/)
    end

    it "reports a day past the length of its month" do
      messages.("SET a '2027-02-30'\n").first.should.match(/has day 30 in a month with 29/)
      messages.("SET a '2027-04-31'\n").first.should.match(/has day 31 in a month with 30/)
    end

    it "accepts 29 February, which some years have" do
      lint.("SET a '2028-02-29'\n").should.be.empty
    end

    it "accepts the last day of a 31-day month" do
      lint.("SET a '2027-01-31'\n").should.be.empty
    end
  end

  it "accepts the slash separator" do
    lint.("SET a '2027/01/31'\n").should.be.empty
    messages.("SET a '1970/01/01'\n").length.should == 1
  end

  it "reports every bad constant on a line" do
    messages.("IF ['1970-01-01' < '9999-01-01']\n").length.should == 2
  end

  it "says nothing about a datetime constant in range" do
    lint.("SET a '2027-01-01@14:33'\n").should.be.empty
  end

  it "says nothing about an ordinary string that looks like a date" do
    # Double quotes make it a STRING, not a DATE.
    lint.(%(SET a "1970-01-01"\n)).should.be.empty
  end

  it "says nothing about comments" do
    lint.("# SET a '1970-01-01'\n").should.be.empty
  end

  it "points at the constant" do
    text = "SET a '1970-01-01'\n"

    lint.(text).first.column.should == text.index("'") + 1
  end

  it "reports at error severity" do
    lint.("SET a '1970-01-01'\n").first.severity.should == "error"
  end
end
