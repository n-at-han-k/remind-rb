# frozen_string_literal: true

require_relative "../rule"

module RemLint
  module Rules
    # Hebrew dates that cannot exist.
    #
    # `hebdate(day, month, year)` returns `Invalid Hebrew date` for a month
    # Remind does not know and for a day past that month's length. Both are
    # decidable from literals, and both fail on the day the reminder would
    # otherwise have fired.
    #
    # The lengths are `MaxMonLen[]` from src/hbcal.c, and they are *not* the
    # textbook fixed ones: Heshvan and Kislev are recomputed from each year's
    # length -- a Hebrew year runs 353, 354 or 355 days -- so this reports the
    # maximum any year allows. Confirmed against the binary across seven
    # consecutive years.
    #
    # The names are all three of Remind's tables: `HebMonthNames`,
    # `IvritMonthNames` in Hebrew script, and `AltMonthSpellings`, which is why
    # `Tishri`, `Cheshvan`, `Shevat`, `Tammuz`, `Iyyar`, `Adar I` and their
    # Hebrew equivalents are all accepted. Missing that third table reports 31
    # offences against Remind's own tests/test.rem.
    #
    # `hebmon()` returns the canonical transliteration, so a comparison against
    # an accepted-but-non-canonical spelling is never true even where `hebdate`
    # takes it -- which the message says.
    class HebrewDate < Rule
      # `MaxMonLen[]` from src/hbcal.c, in the order its month constants
      # define: Tishrey, Heshvan, Kislev, Tevet, Shvat, Adar A, Adar B,
      # Nisan, Iyar, Sivan, Tamuz, Av, Elul, Adar.
      MAX_LENGTHS = [30, 30, 30, 29, 30, 30, 29, 30, 29, 30, 29, 30, 29, 29].freeze

      CANONICAL = [
        "Tishrey", "Heshvan", "Kislev", "Tevet", "Shvat", "Adar A", "Adar B",
        "Nisan", "Iyar", "Sivan", "Tamuz", "Av", "Elul", "Adar"
      ].freeze

      # `IvritMonthNames` -- the same months in Hebrew script.
      IVRIT = [
        "\u05EA\u05E9\u05E8\u05D9", "\u05D7\u05E9\u05D5\u05D5\u05DF",
        "\u05DB\u05E1\u05DC\u05D5", "\u05D8\u05D1\u05EA",
        "\u05E9\u05D1\u05D8", "\u05D0\u05D3\u05E8 \u05D0'",
        "\u05D0\u05D3\u05E8 \u05D1'", "\u05E0\u05D9\u05E1\u05DF",
        "\u05D0\u05D9\u05D9\u05E8", "\u05E1\u05D9\u05D5\u05DF",
        "\u05EA\u05DE\u05D5\u05D6", "\u05D0\u05D1",
        "\u05D0\u05DC\u05D5\u05DC", "\u05D0\u05D3\u05E8"
      ].freeze

      # `AltMonthSpellings` -- name => the month index it resolves to.
      ALTERNATES = {
        "Tishri"                    => 0,
        "Tishrei"                   => 0,
        "Cheshvan"                  => 1,
        "Kheshvan"                  => 1,
        "Shevat"                    => 4,
        "Tammuz"                    => 10,
        "Adar 1"                    => 5,
        "Adar I"                    => 5,
        "\u05D0\u05D3\u05E8 \u05D0" => 5,
        "\u05D0\u05D3\u05E8 1"      => 5,
        "\u05D0\u05D3\u05E8 I"      => 5,
        "Adar 2"                    => 6,
        "Adar II"                   => 6,
        "\u05D0\u05D3\u05E8 \u05D1" => 6,
        "\u05D0\u05D3\u05E8 2"      => 6,
        "\u05D0\u05D3\u05E8 II"     => 6,
        "Iyyar"                     => 8,
      }.freeze

      MONTHS = (
        CANONICAL.each_with_index.to_h { |name, index| [name.downcase, MAX_LENGTHS[index]] }
          .merge(IVRIT.each_with_index.to_h { |name, index| [name, MAX_LENGTHS[index]] })
          .merge(ALTERNATES.transform_keys(&:downcase)
                           .transform_values { |index| MAX_LENGTHS[index] })
      ).freeze

      # `hebdate(30, "Elul", 5790)` and the two-argument form.
      CALL = /\bhebdate\s*\(\s*(?<day>\d+)\s*,\s*"(?<month>[^"]+)"/i

      def self.default_severity
        "error"
      end

      def self.description
        "A Hebrew month Remind does not know, or a day past that month's length."
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
          logical_line.text.to_enum(:scan, CALL).each do
            match = Regexp.last_match

            report(logical_line, match)
          end
        end

        def report(logical_line, match)
          month = match[:month].strip
          longest = MONTHS[month.downcase]

          if longest.nil?
            offend_at(logical_line, match.begin(0), unknown_message(month))
          elsif match[:day].to_i < 1 || match[:day].to_i > longest
            offend_at(logical_line, match.begin(0), length_message(match[:day], month, longest))
          end
        end

        def unknown_message(month)
          "`#{month}` is not a Hebrew month Remind knows; `hebdate` returns " \
          "`Invalid Hebrew date`, and `hebmon()` returns the canonical spelling, " \
          "so a comparison against this is never true either"
        end

        def length_message(day, month, longest)
          "`#{month}` never has #{day} days -- #{longest} at most -- so `hebdate` " \
          "returns `Invalid Hebrew date`"
        end
    end
  end
end

__END__

require_relative "../document"

describe "RemLint::Rules::HebrewDate" do
  lint = proc do |text|
    source = RemLint::Source.new(path: "t.rem", text: text)

    RemLint::Rules::HebrewDate.new.run(RemLint::Document.new(source))
  end

  messages = proc { |text| lint.(text).map(&:message) }

  describe "dates that exist" do
    it "accepts a 30-day month at 30" do
      lint.(%(MSG [hebdate(30, "Nisan", 5790)]\n)).should.be.empty
      lint.(%(MSG [hebdate(30, "Tishrey", 5790)]\n)).should.be.empty
    end

    it "accepts the months whose length varies by year at 30" do
      # Heshvan and Kislev are 29 or 30 depending on the year's length.
      lint.(%(MSG [hebdate(30, "Heshvan", 5790)]\n)).should.be.empty
      lint.(%(MSG [hebdate(30, "Kislev", 5790)]\n)).should.be.empty
    end

    it "accepts a 29-day month at 29" do
      lint.(%(MSG [hebdate(29, "Elul", 5790)]\n)).should.be.empty
    end

    it "accepts the leap-month spellings" do
      lint.(%(MSG [hebdate(29, "Adar A", 5790)]\n)).should.be.empty
      lint.(%(MSG [hebdate(29, "Adar B", 5790)]\n)).should.be.empty
    end

    it "accepts the alternate spellings Remind lists" do
      # tests/test.rem exercises every one of these.
      %w[Tishri Tishrei Cheshvan Kheshvan Shevat Tammuz Iyyar].each do |name|
        lint.(%(MSG [hebdate(1, "#{name}", 5790)]\n)).should.be.empty
      end
    end

    it "accepts the Adar variants" do
      ["Adar 1", "Adar I", "Adar 2", "Adar II"].each do |name|
        lint.(%(MSG [hebdate(1, "#{name}", 5790)]\n)).should.be.empty
      end
    end

    it "accepts the Hebrew-script names" do
      lint.(%(MSG [hebdate(1, "\u05EA\u05E9\u05E8\u05D9", 5790)]\n)).should.be.empty
      lint.(%(MSG [hebdate(1, "\u05D0\u05DC\u05D5\u05DC", 5790)]\n)).should.be.empty
    end

    it "applies the right length to an alternate spelling" do
      # Cheshvan is Heshvan, which reaches 30; Tammuz is Tamuz, which does not.
      lint.(%(MSG [hebdate(30, "Cheshvan", 5790)]\n)).should.be.empty
      lint.(%(MSG [hebdate(30, "Tammuz", 5790)]\n)).length.should == 1
    end

    it "matches the month name case-insensitively" do
      lint.(%(MSG [hebdate(29, "elul", 5790)]\n)).should.be.empty
    end
  end

  describe "dates that cannot exist" do
    it "reports a day past a 29-day month" do
      # The book's example, confirmed against Remind.
      messages.(%(MSG [hebdate(30, "Elul", 5790)]\n)).first.should ==
        "`Elul` never has 30 days -- 29 at most -- so `hebdate` returns `Invalid Hebrew date`"
    end

    it "reports Tevet at 30" do
      messages.(%(MSG [hebdate(30, "Tevet", 5790)]\n)).length.should == 1
    end

    it "reports a day past every month" do
      messages.(%(MSG [hebdate(31, "Nisan", 5790)]\n)).length.should == 1
    end

    it "reports a day of zero" do
      messages.(%(MSG [hebdate(0, "Nisan", 5790)]\n)).length.should == 1
    end

    it "reports a month Remind does not know" do
      messages.(%(MSG [hebdate(1, "Nosuch", 5790)]\n)).first.should.match(
        /is not a Hebrew month Remind knows/,
      )
    end

    it "mentions that hebmon returns the canonical spelling" do
      messages.(%(MSG [hebdate(1, "Nosuch", 5790)]\n)).first.should.match(
        /`hebmon\(\)` returns the canonical spelling/,
      )
    end

    it "points at the call" do
      text = %(MSG [hebdate(30, "Elul", 5790)]\n)

      lint.(text).first.column.should == text.index("hebdate") + 1
    end
  end

  it "says nothing about a computed day" do
    lint.(%(MSG [hebdate(d, "Elul", 5790)]\n)).should.be.empty
  end

  it "says nothing about comments" do
    lint.(%(# MSG [hebdate(30, "Elul", 5790)]\n)).should.be.empty
  end

  it "reports at error severity" do
    lint.(%(MSG [hebdate(30, "Elul", 5790)]\n)).first.severity.should == "error"
  end
end
