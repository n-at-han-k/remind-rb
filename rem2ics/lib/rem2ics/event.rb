# frozen_string_literal: true

require "digest"
require "icalendar"

require_relative "recurrence"

module Rem2ics
  # One reminder, as an iCalendar event.
  #
  # The iCalendar is built with the icalendar gem rather than by printing
  # lines: escaping, folding at 75 octets, CRLF endings and DTSTAMP are all
  # spelled out in RFC 5545, all fiddly, and all already written.
  #
  # What is decided here is the mapping, and it is a small list:
  #
  #   the reminder's message   SUMMARY, from Remind's CAL_MODE rendering,
  #                            which is where a %"…%" title is honoured
  #   the rest of the message  DESCRIPTION, from the NORMAL_MODE rendering
  #   the trigger              DTSTART, and RRULE or RDATE (see Recurrence)
  #   AT                       the time on DTSTART
  #   DURATION                 DTEND
  #   +n advance warning       VALARM, n days or n minutes before
  class Event
    # A reminder with no AT clause is an all-day event, and an all-day event's
    # DTEND is the day after: the RFC's end is exclusive.
    ALL_DAY = 1

    MINUTES_PER_HOUR = 60

    # UIDs have to survive re-importing the same file, or every conversion
    # creates duplicates instead of updating what is there. A digest of the
    # reminder as written plus the date it starts on is stable across runs and
    # different between reminders.
    UID_SUFFIX = "rem2ics"

    attr_reader :reminder, :recurrence, :organizer

    def initialize(reminder, recurrence:, organizer:)
      @reminder = reminder
      @recurrence = recurrence
      @organizer = organizer
    end

    def to_ical_event
      Icalendar::Event.new.tap do |event|
        event.uid = uid
        event.summary = reminder.summary
        event.description = reminder.description
        event.organizer = Icalendar::Values::CalAddress.new("mailto:#{organizer}")
        event.ip_class = "PUBLIC"

        add_dates(event)
        add_recurrence(event)
        add_alarms(event)
      end
    end

    private

      def uid
        digest = Digest::SHA256.hexdigest("#{reminder.line}\n#{start_date}")

        "#{digest[0, 32]}@#{UID_SUFFIX}"
      end

      def start_date
        recurrence.dates.first
      end

      def add_dates(event)
        if reminder.at
          add_timed(event)
        else
          add_all_day(event)
        end
      end

      def add_all_day(event)
        event.dtstart = Icalendar::Values::Date.new(start_date)
        event.dtend = Icalendar::Values::Date.new(start_date + ALL_DAY)
      end

      # Local wall-clock time, with no zone: a reminder file says nothing
      # about zones, and the calendar it lands in is the reader's own.
      def add_timed(event)
        event.dtstart = Icalendar::Values::DateTime.new(starts_at)

        if reminder.duration
          event.dtend = Icalendar::Values::DateTime.new(starts_at + minutes(reminder.duration))
        end
      end

      def starts_at
        DateTime.new(
          start_date.year,
          start_date.month,
          start_date.day,
        ) + minutes(reminder.at)
      end

      def minutes(count)
        Rational(count, 24 * 60)
      end

      # A rule when the rule was checked against Remind and agreed; otherwise
      # the dates Remind gave, which are exact but finite.
      def add_recurrence(event)
        if recurrence.rule?
          event.rrule = recurrence.text
        else
          add_dates_after_the_first(event)
        end
      end

      def add_dates_after_the_first(event)
        recurrence.dates.drop(1).each do |date|
          event.append_rdate(Icalendar::Values::Date.new(date))
        end
      end

      # Remind writes advance warning two ways: `+n` on the trigger is n days
      # before the day, `+n` on the AT clause is n minutes before the time.
      def add_alarms(event)
        alarm(event, "-P#{reminder.warning_days}D", reminder.warning_days)
        alarm(event, "-PT#{reminder.warning_minutes}M", reminder.warning_minutes)
      end

      def alarm(event, trigger, wanted)
        if wanted
          event.alarm do |alarm|
            alarm.action = "DISPLAY"
            alarm.trigger = trigger
            alarm.description = reminder.summary
          end
        end
      end
  end
end

__END__

require "remind"

describe "Rem2ics::Event" do
  session = Remind::Session.new
  session.today = Date.new(2026, 8, 19)

  ical = proc do |line|
    reminder = Remind::Reminder.parse(line, session: session)
    recurrence = Rem2ics::Recurrence.new(reminder, horizon: 12).call

    Rem2ics::Event.new(reminder, recurrence: recurrence, organizer: "me@host")
                  .to_ical_event
                  .to_ical
  end

  describe "an all-day reminder" do
    it "starts on the day Remind says, as a date" do
      ical.("REM 25 Dec MSG christmas").should.include "DTSTART;VALUE=DATE:20261225"
    end

    it "ends the next day, because the RFC's end is exclusive" do
      ical.("REM 25 Dec MSG christmas").should.include "DTEND;VALUE=DATE:20261226"
    end
  end

  describe "a timed reminder" do
    it "starts at the time the AT clause gave" do
      ical.("REM Mon AT 9:30 MSG standup").should.include "DTSTART:20260824T093000"
    end

    it "ends a DURATION later" do
      ical.("REM Mon AT 9:30 DURATION 1:30 MSG standup").should.include "DTEND:20260824T110000"
    end

    it "has no end at all when the reminder gave no duration" do
      ical.("REM Mon AT 9:30 MSG standup").should.not.include "DTEND"
    end
  end

  describe "the message" do
    it "takes the title Remind marks for a calendar" do
      output = ical.(%q{REM 25 Dec MSG %"christmas%" buy a tree})

      output.should.include "SUMMARY:christmas"
      output.should.include "DESCRIPTION:christmas buy a tree"
    end

    it "escapes what iCalendar gives meaning to" do
      ical.("REM 25 Dec MSG lunch, then presents").should.include "lunch\\, then presents"
    end
  end

  describe "recurrence" do
    it "carries a rule that agreed with Remind" do
      ical.("REM Mon MSG gym").should.include "RRULE:FREQ=WEEKLY;BYDAY=MO"
    end

    it "carries dates instead of a rule that did not" do
      output = ical.("REM 1 Mar SKIP OMIT Sat Sun MSG payday")

      output.should.not.include "RRULE"
      output.should.include "RDATE"
    end

    it "carries neither for a reminder that happens once" do
      output = ical.("REM 25 Dec 2027 MSG christmas")

      output.should.not.include "RRULE"
      output.should.not.include "RDATE"
    end
  end

  describe "alarms" do
    it "warns the days ahead the trigger asked for" do
      ical.("REM 15 +3 MSG rent").should.include "TRIGGER:-P3D"
    end

    it "warns the minutes ahead the AT clause asked for" do
      ical.("REM Mon AT 9:30 +15 MSG standup").should.include "TRIGGER:-PT15M"
    end

    it "has no alarm when the reminder asked for none" do
      ical.("REM 25 Dec MSG christmas").should.not.include "VALARM"
    end
  end

  describe "identity" do
    it "gives the same reminder the same UID every run" do
      ical.("REM 25 Dec MSG christmas")[/UID:(\S+)/, 1]
          .should == ical.("REM 25 Dec MSG christmas")[/UID:(\S+)/, 1]
    end

    it "gives different reminders different UIDs" do
      ical.("REM 25 Dec MSG christmas")[/UID:(\S+)/, 1]
          .should.not == ical.("REM 26 Dec MSG boxing day")[/UID:(\S+)/, 1]
    end
  end
end
