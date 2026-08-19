# frozen_string_literal: true

require "etc"
require "icalendar"
require "remind"

require_relative "event"
require_relative "recurrence"
require_relative "version"

module Rem2ics
  # Reminder files in, one iCalendar out.
  #
  # The conversion is a fold over what Remind gives: every reminder in every
  # file becomes an event, in file order, in one VCALENDAR. What it skips is
  # what a calendar has nowhere to put -- RUN reminders execute shell
  # commands, CAL and PS reminders draw on a PostScript calendar, and none of
  # them is an appointment.
  #
  # "Today" is pinned for the whole conversion, because it is what a relative
  # trigger is relative to: `REM Mon` starts on a different Monday depending
  # on when it is asked. Pinning it makes the same file convert to the same
  # calendar every time, which is what makes the output diffable and the
  # conversion testable.
  class Converter
    PRODID = "-//rem2ics//NONSGML rem2ics #{VERSION}//EN"

    attr_reader :session, :horizon, :organizer, :warnings

    def initialize(
      session: Remind::Session.new,
      horizon: Recurrence::DEFAULT_HORIZON,
      organizer: nil,
      warnings: $stderr
    )
      @session = session
      @horizon = horizon
      @organizer = organizer || self.class.local_address
      @warnings = warnings
    end

    # `id -nu`@`uname -n`, which is what the Perl this descends from used, and
    # is as good a guess at an organizer as a reminder file can support.
    def self.local_address
      login = Etc.getlogin || ENV.fetch("USER", "remind")

      "#{login}@#{Etc.uname.fetch(:nodename)}"
    end

    def call(paths, today: Date.today)
      session.today = today

      calendar.tap do |ical|
        paths.each { |path| add_file(ical, path) }
      end
    end

    private

      def calendar
        Icalendar::Calendar.new.tap do |ical|
          ical.prodid = PRODID
          ical.ip_method = "PUBLISH"
        end
      end

      def add_file(ical, path)
        Remind::Source.new(path, session: session).reminders.each do |reminder|
          add_reminder(ical, reminder)
        end
      rescue Remind::EvaluationError => error
        warnings.puts("#{path}: #{error.message}")
      end

      def add_reminder(ical, reminder)
        if reminder.display?
          ical.add_event(event_for(reminder))
        end
      end

      # The message is rendered as of the day the event starts, not as of the
      # day the conversion runs: `%b` says "today" on the day, and a calendar
      # entry that says "in 27 days' time" forever is a calendar entry that
      # was written on the wrong day.
      def event_for(reminder)
        recurrence = Recurrence.new(reminder, horizon: horizon).call

        Event.new(
          reminder.as_of(recurrence.dates.first),
          recurrence: recurrence,
          organizer:  organizer,
        ).to_ical_event
      end
  end
end

__END__

require "tempfile"

describe "Rem2ics::Converter" do
  written = proc do |text|
    file = Tempfile.new(["reminders", ".rem"])
    file.write(text)
    file.close
    file.path
  end

  convert = proc do |text, today = Date.new(2026, 8, 19)|
    Rem2ics::Converter.new(organizer: "me@host", horizon: 12)
                      .call([written.(text)], today: today)
                      .to_ical
  end

  it "wraps the events in one calendar" do
    output = convert.("REM 25 Dec MSG christmas\n")

    output.should.start_with "BEGIN:VCALENDAR"
    output.should.include "PRODID:-//rem2ics//NONSGML rem2ics"
    output.should.include "METHOD:PUBLISH"
    output.should.end_with "END:VCALENDAR\r\n"
  end

  it "converts every reminder in the file, in order" do
    output = convert.(<<~REM)
      REM 25 Dec MSG christmas
      REM Mon MSG gym
    REM

    output.scan(/SUMMARY:(\w+)/).flatten.should == %w[christmas gym]
  end

  it "skips what a calendar cannot show" do
    output = convert.(<<~REM)
      REM 25 Dec MSG christmas
      REM Mon RUN backup.sh
      SET a 1
    REM

    output.scan(/BEGIN:VEVENT/).length.should == 1
  end

  it "pins today, so the same file converts to the same calendar" do
    first = convert.("REM Mon MSG gym\n")
    again = convert.("REM Mon MSG gym\n")

    first.sub(/DTSTAMP:\S+/, "").should == again.sub(/DTSTAMP:\S+/, "")
  end

  it "starts a relative reminder from the day it was told about" do
    convert.("REM Mon MSG gym\n", Date.new(2027, 3, 1)).should.include "DTSTART;VALUE=DATE:20270301"
  end

  it "says so when a file cannot be read, and carries on" do
    warnings = StringIO.new
    converter = Rem2ics::Converter.new(organizer: "me@host", warnings: warnings)

    converter.call(["/nonexistent.rem"], today: Date.new(2026, 8, 19)).to_ical
             .should.include "BEGIN:VCALENDAR"
    warnings.string.should.include "/nonexistent.rem"
  end
end
