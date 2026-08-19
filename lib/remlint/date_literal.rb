# frozen_string_literal: true

require_relative "vocabulary"

module RemLint
  # A fully-specified date written out in a trigger.
  #
  # Remind accepts the three components in any order -- `1 Jan 2027`,
  # `Jan 1 2027` and `2027 Jan 1` are the same date to `GetFullDate` -- so this
  # collects components rather than matching a shape.
  CalendarDate = Struct.new(:year, :month, :day) do
    # Days from 1990-01-01, the same epoch Remind counts from (`BASE` in
    # src/custom.h.in). Only ever compared against another one of these, so it
    # needs to be monotonic rather than meaningful.
    def to_i
      (year * 10_000) + (month * 100) + day
    end

    def to_s
      format(
        "%04d-%02d-%02d",
        year,
        month,
        day,
      )
    end

    def <=>(other)
      to_i <=> other.to_i
    end

    include Comparable
  end

  # Reads a date out of a run of tokens, the way `GetFullDate` does.
  #
  # The classification is `FindNumericToken`'s (src/token.c): a number from
  # 1990 to 5990 is a year, a number from 1 to 31 is a day, and `YYYY-MM-DD`
  # is a date all by itself. There is no overlap to resolve -- years start
  # above the largest day -- so the components can arrive in any order.
  #
  # Returns nil unless all three components turn up, because a partial date is
  # a different question from a wrong one, and the rules that care about
  # partial dates want to ask it separately.
  module DateLiteral
    EPOCH_YEAR = 1990

    # `BASE` + `YR_RANGE` from src/custom.h.in.
    LAST_YEAR = EPOCH_YEAR + 4000

    MAX_DAY = 31

    SEPARATORS = %w[- /].freeze

    module_function

    # Scans forward from `index` and returns [date, tokens consumed]. Consumed
    # is zero when nothing date-shaped was there at all.
    def scan(tokens, index)
      state = { year: nil, month: nil, day: nil }
      cursor = index

      while cursor < tokens.length
        taken = absorb(tokens, cursor, state)

        if taken.zero?
          break
        end

        cursor += taken
      end

      [complete(state), cursor - index]
    end

    # The date at `index`, or nil.
    def at(tokens, index)
      scan(tokens, index).first
    end

    def absorb(tokens, cursor, state)
      iso = iso_date(tokens, cursor)

      if iso
        merge(state, iso)
        5
      else
        component(tokens[cursor], state)
      end
    end

    # `2027-01-01` reaches the lexer as five tokens, because a hyphen is an
    # operator everywhere else.
    def iso_date(tokens, cursor)
      window = tokens[cursor, 5]

      if window&.length == 5 && iso_shape?(window)
        { year: window[0].value.to_i, month: window[2].value.to_i, day: window[4].value.to_i }
      end
    end

    def iso_shape?(window)
      window[0].type == :number && window[2].type == :number && window[4].type == :number &&
        SEPARATORS.include?(window[1].value) && window[1].value == window[3].value &&
        window[0].value.length == 4
    end

    def component(token, state)
      value = classify(token)

      if value.nil? || !state[value.first].nil?
        0
      else
        state[value.first] = value.last
        1
      end
    end

    def classify(token)
      case token.type
      when :number then number(token.value)
      when :name   then month(token.value)
      end
    end

    def number(text)
      value = Integer(text, exception: false)

      if value.nil?
        nil
      elsif value >= EPOCH_YEAR && value <= LAST_YEAR
        [:year, value]
      elsif value >= 1 && value <= MAX_DAY
        [:day, value]
      end
    end

    # Month names abbreviate like every other keyword: `Jan` is `JANUARY`
    # because its minimum length is 3.
    def month(word)
      keyword = Vocabulary.keyword(word)

      if keyword&.type == "T_Month"
        [:month, MONTHS.index(keyword.name) + 1]
      end
    end

    MONTHS = %w[
      JANUARY FEBRUARY MARCH APRIL MAY JUNE
      JULY AUGUST SEPTEMBER OCTOBER NOVEMBER DECEMBER
    ].freeze

    def merge(state, components)
      components.each do |key, value|
        state[key] ||= value
      end
    end

    def complete(state)
      if state.values.none?(&:nil?)
        CalendarDate.new(state[:year], state[:month], state[:day])
      end
    end
  end
end

__END__

require_relative "document"

describe "RemLint::DateLiteral" do
  tokens = proc do |text|
    source = RemLint::Source.new(path: "t.rem", text: text)
    document = RemLint::Document.new(source)

    document.tokens_for(document.logical_lines.first)
  end

  date = proc { |text| RemLint::DateLiteral.at(tokens.(text), 0) }

  describe "the spelled-out form" do
    it "reads day, month, year" do
      date.("1 Jan 2027").to_s.should == "2027-01-01"
    end

    it "reads month, day, year" do
      date.("Jan 1 2027").to_s.should == "2027-01-01"
    end

    it "reads them in any other order, as GetFullDate does" do
      date.("2027 Jan 1").to_s.should == "2027-01-01"
      date.("2027 1 Jan").to_s.should == "2027-01-01"
    end

    it "reads a full month name" do
      date.("15 September 2026").to_s.should == "2026-09-15"
    end

    it "reads an abbreviated month name" do
      date.("15 Sep 2026").to_s.should == "2026-09-15"
      date.("15 sept 2026").to_s.should == "2026-09-15"
    end

    it "reads December, the last month" do
      date.("31 Dec 2026").to_s.should == "2026-12-31"
    end
  end

  describe "the ISO form" do
    it "reads a hyphenated date" do
      date.("2027-01-01").to_s.should == "2027-01-01"
    end

    it "reads a slashed date" do
      date.("2027/03/15").to_s.should == "2027-03-15"
    end

    it "does not read a mixed separator" do
      date.("2027-03/15").should.be.nil
    end

    it "does not read a subtraction as a date" do
      date.("2027 - 3").should.be.nil
    end
  end

  describe "dates it will not complete" do
    it "returns nil for a partial date" do
      date.("1 Jan").should.be.nil
      date.("Jan 2027").should.be.nil
      date.("2027").should.be.nil
    end

    it "returns nil for nothing date-shaped at all" do
      date.("MSG hello").should.be.nil
    end

    it "returns nil for a number outside both ranges" do
      # 1900 is neither a year Remind represents nor a day.
      date.("32 Jan 1900").should.be.nil
    end
  end

  describe "component classification" do
    it "treats 1990 as the first year, not a day" do
      date.("1 Jan 1990").to_s.should == "1990-01-01"
    end

    it "treats 5990 as the last year" do
      date.("1 Jan 5990").to_s.should == "5990-01-01"
    end

    it "treats 31 as a day" do
      date.("31 Jan 2027").to_s.should == "2027-01-31"
    end

    it "stops at a component it already has" do
      # The second month name is not part of this date.
      RemLint::DateLiteral.scan(tokens.("1 Jan 2027 Feb"), 0).last.should == 3
    end
  end

  describe "scanning from an offset" do
    it "starts where it is told to" do
      stream = tokens.("REM 1 Jan 2027 MSG hi")

      RemLint::DateLiteral.at(stream, 1).to_s.should == "2027-01-01"
    end

    it "reports how many tokens it took" do
      RemLint::DateLiteral.scan(tokens.("1 Jan 2027"), 0).last.should == 3
      RemLint::DateLiteral.scan(tokens.("2027-01-01"), 0).last.should == 5
    end
  end

  describe "comparison" do
    it "orders dates" do
      (date.("1 Jan 2027") < date.("2 Jan 2027")).should.be.true
      (date.("31 Dec 2026") < date.("1 Jan 2027")).should.be.true
      (date.("1 Jan 2027") == date.("2027-01-01")).should.be.true
    end
  end
end
