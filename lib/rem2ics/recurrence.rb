# frozen_string_literal: true

require "ice_cube"

module Rem2ics
  # How a reminder repeats, expressed the way iCalendar expresses it -- when
  # iCalendar can express it at all.
  #
  # A reminder's trigger and an RRULE overlap, but neither contains the other.
  # `REM 15` and `FREQ=MONTHLY;BYMONTHDAY=15` are the same thing. `REM Mon 13
  # SKIP OMIT Sat Sun` is not any RRULE: it means "the Monday of the week the
  # 13th falls in, unless that lands on an omitted day, in which case do not
  # trigger at all", and BYDAY has no way to say the second half.
  #
  # So the rule is a guess, and the guess is checked. `Remind::Reminder` can
  # produce the dates the reminder actually fires on -- they come from
  # ComputeTrigger, which is what `remind` itself runs -- so the candidate
  # RRULE is expanded with ice_cube and compared against them. If they agree
  # for the whole horizon, the event carries the rule, and every calendar that
  # reads it recurs forever, correctly. If they disagree anywhere, the event
  # carries Remind's dates instead: fewer of them, but none of them wrong.
  #
  # That check is the reason this converter is built on bindings rather than
  # on a parser of its own. Without Remind there is nothing to check against,
  # and every previous converter has had to guess and hope.
  class Recurrence
    # How many occurrences the guess has to get right. Ten years of a monthly
    # reminder, or two of a weekly one -- far enough out for the leap years,
    # the month lengths and the moving holidays that break a rule to have
    # shown up.
    DEFAULT_HORIZON = 120

    # A rule that agreed with Remind for the whole horizon.
    Rule = Struct.new(:text, :dates) do
      def rule?
        true
      end
    end

    # Remind's dates, for a reminder no rule describes.
    Dates = Struct.new(:dates) do
      def rule?
        false
      end

      def text
        nil
      end
    end

    attr_reader :reminder, :horizon

    def initialize(reminder, horizon: DEFAULT_HORIZON)
      @reminder = reminder
      @horizon = horizon
    end

    def call
      if single?
        Dates.new(remind_dates)
      elsif agrees?
        Rule.new(candidate, remind_dates)
      else
        Dates.new(remind_dates)
      end
    end

    # A reminder Remind only ever triggers once needs no rule to describe it,
    # whatever its trigger looks like. Asking Remind is more reliable than
    # reading the trigger: `REM 25 Dec 2027` and `REM 1 Jan 2027 *14 UNTIL 14
    # Jan 2027` both happen once, and only one of them looks like it.
    def single?
      remind_dates.length <= 1
    end

    # The dates Remind says the reminder fires on, bounded by the horizon.
    def remind_dates
      @remind_dates ||= reminder.occurrences(limit: horizon).to_a
    end

    # The RRULE this reminder looks like it means, before anyone checks.
    #
    # The shape is decided by which parts of the date the trigger left out,
    # because that is how Remind's trigger language works: `REM 15` says
    # nothing about the month, so it happens every month.
    def candidate
      @candidate ||= bounded(frequency)
    end

    private

      def frequency
        if reminder.repeat
          "FREQ=DAILY;INTERVAL=#{reminder.repeat}"
        elsif weekday_and_day?
          "FREQ=MONTHLY;BYDAY=#{weekdays};#{week_containing(reminder.day)}"
        elsif weekday_only?
          "FREQ=WEEKLY;BYDAY=#{weekdays}#{in_month}"
        elsif last_day_of_month?
          "FREQ=MONTHLY;BYMONTHDAY=-#{reminder.back}"
        elsif yearly?
          "FREQ=YEARLY;BYMONTH=#{reminder.month};BYMONTHDAY=#{reminder.day}"
        elsif monthly?
          "FREQ=MONTHLY;BYMONTHDAY=#{reminder.day}"
        elsif within_month?
          "FREQ=DAILY;BYMONTH=#{reminder.month}"
        else
          "FREQ=DAILY"
        end
      end

      def weekdays
        reminder.weekdays.join(",")
      end

      def weekday_only?
        reminder.weekdays.any? && reminder.day.nil?
      end

      def weekday_and_day?
        reminder.weekdays.any? && !reminder.day.nil?
      end

      # `REM Mon Jun` is every Monday, but only in June.
      def in_month
        if reminder.month
          ";BYMONTH=#{reminder.month}"
        else
          ""
        end
      end

      # `REM Wed 15` is the Wednesday on or after the 15th, which is not the
      # third Wednesday of the month -- in a month whose 1st is a Wednesday
      # they are a week apart. What it is, exactly, is the Wednesday inside
      # the seven days starting on the 15th, and BYMONTHDAY can say that.
      def week_containing(day)
        "BYMONTHDAY=#{(day..(day + 6)).to_a.join(",")}"
      end

      # `REM 1 -1` is the 1st, counted back one day: the last day of the month
      # before. BYMONTHDAY counts back from the end of the month the same way.
      def last_day_of_month?
        reminder.day == 1 && reminder.back.to_i > 0
      end

      def yearly?
        reminder.day && reminder.month
      end

      def monthly?
        reminder.day && reminder.month.nil?
      end

      # `REM Feb` is every day in February.
      def within_month?
        reminder.day.nil? && reminder.month
      end

      # Where the series stops, if it does.
      #
      # An UNTIL clause says so outright. So does a year in a trigger that
      # leaves the day or the month out: `REM Sat Sun 2021` is every weekend
      # *in 2021*, and a rule without an UNTIL would go on for ever. A year in
      # a fully-specified trigger is a start date rather than a bound, and a
      # `*n` repeat starts from its date rather than being confined to it, so
      # neither of those closes anything.
      #
      # Failing all that, a walk that ran out before the horizon says the
      # reminder stops on its own, and where.
      def bounded(rule)
        last = reminder.until_date || year_end || ran_out

        if last
          "#{rule};UNTIL=#{last.strftime("%Y%m%d")}"
        else
          rule
        end
      end

      def year_end
        if reminder.year && !reminder.repeat && partial?
          Date.new(reminder.year, 12, 31)
        end
      end

      def partial?
        reminder.day.nil? || reminder.month.nil?
      end

      def ran_out
        if remind_dates.length < horizon
          remind_dates.last
        end
      end

      # --- the check --------------------------------------------------------

      def agrees?
        expanded == remind_dates
      end

      # The candidate rule's own dates, seeded at the first date Remind gives,
      # since DTSTART is where a calendar starts expanding it.
      def expanded
        if parsed_rule
          schedule(parsed_rule).first(remind_dates.length).map(&:to_date)
        else
          []
        end
      end

      # A rule nobody can expand is a rule this converter will not emit. The
      # rescue is around the parse alone: an error anywhere else is a bug
      # here, and swallowing it would turn every bug into a silent fallback.
      def parsed_rule
        IceCube::Rule.from_ical(candidate)
      rescue ArgumentError, RangeError
        nil
      end

      def schedule(rule)
        start = remind_dates.first

        IceCube::Schedule.new(Time.new(start.year, start.month, start.day)) do |built|
          built.add_recurrence_rule(rule)
        end
      end
  end
end

__END__

require "remind"

describe "Rem2ics::Recurrence" do
  session = Remind::Session.new
  session.today = Date.new(2026, 8, 19)

  recurrence = proc do |line, horizon = 12|
    Rem2ics::Recurrence.new(Remind::Reminder.parse(line, session: session), horizon: horizon).call
  end

  describe "reminders an RRULE describes" do
    it "makes a weekly reminder a weekly rule" do
      result = recurrence.("REM Mon MSG gym")

      result.should.be.rule
      result.text.should == "FREQ=WEEKLY;BYDAY=MO"
    end

    it "makes a several-weekday reminder one rule" do
      recurrence.("REM Mon Wed Fri MSG gym").text.should == "FREQ=WEEKLY;BYDAY=MO,WE,FR"
    end

    it "makes a day-of-month reminder a monthly rule" do
      recurrence.("REM 15 MSG rent").text.should == "FREQ=MONTHLY;BYMONTHDAY=15"
    end

    it "makes a day-and-month reminder a yearly rule" do
      recurrence.("REM 25 Dec MSG christmas").text.should ==
        "FREQ=YEARLY;BYMONTH=12;BYMONTHDAY=25"
    end

    it "makes a repeat a daily rule with an interval" do
      recurrence.("REM 1 Jan 2027 *14 MSG fortnightly").text.should.start_with "FREQ=DAILY;INTERVAL=14"
    end

    it "bounds a rule by the year the trigger names" do
      # `REM Sat Sun 2031` is every weekend in 2031, and a rule without an
      # UNTIL would run for ever.
      recurrence.("REM Sat Sun 2031 MSG weekends", 8).text
                .should == "FREQ=WEEKLY;BYDAY=SA,SU;UNTIL=20311231"
    end

    it "narrows a weekly rule to the month the trigger names" do
      recurrence.("REM Mon Jun MSG summer mondays").text
                .should == "FREQ=WEEKLY;BYDAY=MO;BYMONTH=6"
    end

    it "counts back from the end of the month when the trigger does" do
      recurrence.("REM 1 -1 MSG last day").text.should == "FREQ=MONTHLY;BYMONTHDAY=-1"
    end

    it "carries an UNTIL through" do
      recurrence.("REM 1 Jan 2027 *7 UNTIL 1 Mar 2027 MSG weekly").text
                .should.include "UNTIL=20270301"
    end

    it "agrees with Remind, which is the only reason it is a rule at all" do
      result = recurrence.("REM 15 MSG rent")

      result.dates.first(3).map(&:to_s).should == %w[2026-09-15 2026-10-15 2026-11-15]
    end
  end

  describe "reminders no RRULE describes" do
    it "falls back to Remind's dates when the reminder skips omitted days" do
      # 1 March 2031 is a Saturday; this reminder does not fire that year.
      result = recurrence.("REM 1 Mar SKIP OMIT Sat Sun MSG payday", 6)

      result.rule?.should.be.false
      result.dates.map(&:to_s).should ==
        %w[2027-03-01 2028-03-01 2029-03-01 2030-03-01 2032-03-01 2033-03-01]
    end

    it "falls back when a trigger names several weekdays and a day" do
      # `REM Wed Thu 15` fires on the *first* of those weekdays on or after
      # the 15th -- one date a month, not two. BYDAY=WE,TH says both, so the
      # check rejects it and the dates go in instead.
      result = recurrence.("REM Wed Thu 15 MSG deadline", 4)

      result.rule?.should.be.false
      result.dates.map(&:to_s).should == %w[2026-08-19 2026-09-16 2026-10-15 2026-11-18]
    end

    it "keeps a rule when one weekday and a day do line up" do
      result = recurrence.("REM Mon 15 MSG deadline", 4)

      result.should.be.rule
      result.text.should == "FREQ=MONTHLY;BYDAY=MO;BYMONTHDAY=15,16,17,18,19,20,21"
    end

    it "keeps the dates rather than a rule that would invent an occurrence" do
      result = recurrence.("REM 1 Mar SKIP OMIT Sat Sun MSG payday", 6)

      result.dates.map(&:to_s).should.not.include "2031-03-01"
    end
  end

  describe "reminders that happen once" do
    it "needs no rule for a reminder Remind triggers once" do
      result = recurrence.("REM 25 Dec 2027 MSG christmas")

      result.rule?.should.be.false
      result.dates.map(&:to_s).should == %w[2027-12-25]
    end

    it "asks Remind rather than reading the trigger" do
      # Fully specified, and still repeating.
      recurrence.("REM 1 Jan 2027 *14 MSG fortnightly").should.be.rule
    end
  end
end
