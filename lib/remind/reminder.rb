# frozen_string_literal: true

require "fiddle"

require_relative "native"
require_relative "session"

module Remind
  # One `REM` line, parsed by Remind.
  #
  # This is the binding that exists because converting a reminder file to
  # anything else is otherwise a re-implementation of Remind. A trigger like
  # `REM Mon 13 SKIP OMIT Sat MSG x` means "the Monday of the week the 13th
  # falls in, unless that is a Saturday, in which case skip it" -- and every
  # program that has tried to read that with a regular expression has got some
  # of it wrong. Here the parse is `ParseRem`, the first date is
  # `ComputeTrigger`, the message is `DoSubst`, and the dates after the first
  # are `ComputeTrigger` again from further along. Nothing about the date
  # specification is interpreted on this side.
  #
  # The fields are Remind's, with two translations and no others: months are
  # 1..12 rather than 0..11, and a field the reminder did not mention is nil
  # rather than Remind's sentinel for it.
  class Reminder
    # What Remind numbers the weekday bits from: bit 0 is Monday.
    WEEKDAY_BITS = %w[MO TU WE TH FR SA SU].freeze

    # A body a calendar can show. RUN reminders execute a shell command, CAL
    # and PS reminders draw on a PostScript calendar; none of them is an
    # event.
    DISPLAY_TYPES = %i[msg msf].freeze

    TYPE_NAMES = {
      msg_type:      :msg,
      msf_type:      :msf,
      run_type:      :run,
      cal_type:      :cal,
      sat_type:      :satisfy,
      passthru_type: :passthru,
    }.freeze

    # How far a walk will go looking for the next occurrence before deciding
    # there isn't one. Remind answers "cannot compute trigger" on its own for
    # most run-out reminders; this bounds the ones it would keep answering.
    DEFAULT_LIMIT = 100

    attr_reader :line, :session, :first, :description, :type

    class << self
      # nil when the line is not a reminder Remind can parse into an event:
      # a comment, a SET, a REM with no body, a trigger that never fires.
      def parse(line, session: Session.new)
        new(line, session: session).tap(&:parse).presented
      rescue EvaluationError
        nil
      end
    end

    def initialize(line, session: Session.new)
      @line = line
      @session = session
      @native = session.native
    end

    # --- what the trigger said -------------------------------------------

    # The day of the month, or nil.
    def day
      field(:d, native.no_day)
    end

    # 1..12, or nil. Remind counts months from zero; this does not.
    def month
      zero_based = field(:m, native.no_month)

      if zero_based
        zero_based + 1
      end
    end

    def year
      field(:y, native.no_year)
    end

    # The weekdays named in the trigger, as RFC 5545 spells them, in Remind's
    # bit order: `REM Mon Wed Fri` is ["MO", "WE", "FR"].
    def weekdays
      bits = trigger_field(:wd)

      WEEKDAY_BITS.each_index.select { |index| bits.anybits?(1 << index) }
                  .map { |index| WEEKDAY_BITS[index] }
    end

    # `REM 1 *7` repeats every seven days. nil when the reminder does not.
    def repeat
      positive(trigger_field(:rep))
    end

    # The last date the reminder may trigger on -- UNTIL or THROUGH -- as a
    # Date, or nil.
    def until_date
      last = field(:until, native.no_until)

      if last
        session.date(last)
      end
    end

    # Advance warning, in days: the `+n` in `REM 15 +3`.
    def warning_days
      positive(trigger_field(:delta))
    end

    # The `-n` in `REM 1 -1`: how many days back from the date the trigger
    # names. `REM 1 -1` is the last day of the month before.
    def back
      positive(trigger_field(:back))
    end

    # Whether the reminder skips or moves over OMITted days, which is a thing
    # no RRULE can say.
    def skip
      trigger_field(:skip)
    end

    def omits_weekdays?
      trigger_field(:localomit) != 0
    end

    def once?
      trigger_field(:once) != 0
    end

    # --- what the AT clause said ------------------------------------------

    # Minutes since midnight, or nil for an all-day reminder.
    def at
      time = timetrig_field(:time)

      if time == native.no_time
        nil
      else
        time
      end
    end

    # DURATION, in minutes, or nil. Remind fills this with the same "no time
    # given" sentinel as the AT clause, not with zero.
    def duration
      given = timetrig_field(:duration)

      if given == native.no_time
        nil
      else
        positive(given)
      end
    end

    # The alarm on an AT clause: `AT 9:30 +15`, in minutes.
    def warning_minutes
      positive(timetrig_field(:delta))
    end

    # --- what it triggers on ----------------------------------------------

    # Every date this reminder triggers on, starting at the first, asked of
    # Remind one at a time. Lazy, because a daily reminder has no last one.
    def occurrences(limit: DEFAULT_LIMIT)
      Enumerator.new do |dates|
        cursor = first_dse
        taken = 0

        while cursor >= 0 && taken < limit
          dates << session.date(cursor)
          taken += 1
          cursor = next_dse(cursor + 1)
        end
      end
    end

    def display?
      DISPLAY_TYPES.include?(type)
    end

    # The same reminder as it reads on a given day.
    #
    # A message is not fixed text: `%b` is "in 27 days' time" or "today"
    # depending on when it is read, and Remind expands it against whatever
    # DSEToday says at the moment it renders. `remind` therefore prints a
    # different message for each occurrence, and anything showing one
    # occurrence should show the message that occurrence would have had.
    #
    # Today is process-wide, so it is pinned and put back.
    def as_of(date)
      was = session.today

      session.today = date
      self.class.parse(line, session: session)
    ensure
      session.today = was
    end

    # --- parsing ----------------------------------------------------------

    def parse
      @trigger = Fiddle::Pointer.malloc(native.sizeof_trigger, Fiddle::RUBY_FREE)
      @timetrig = Fiddle::Pointer.malloc(native.sizeof_timetrig, Fiddle::RUBY_FREE)

      @code, @first_dse, @description = expand(native.normal_mode, @trigger, @timetrig)
      @type = TYPE_NAMES[type_name]
      @first = read_first
    end

    # The message as a calendar wants it: `%"…%"` marks the part of a reminder
    # that is the entry's title, and CAL_MODE is the mode that honours it. A
    # reminder that marks nothing has the whole message for a title.
    #
    # It costs a second parse, because DoSubst consumes the parser as it
    # renders and there is only one message in a line either way.
    def summary
      @summary ||= expand(
        native.cal_mode,
        Fiddle::Pointer.malloc(native.sizeof_trigger, Fiddle::RUBY_FREE),
        Fiddle::Pointer.malloc(native.sizeof_timetrig, Fiddle::RUBY_FREE),
      ).last
    end

    # nil rather than an unusable object, for the caller that is walking a
    # file and does not want to ask about every line twice.
    def presented
      if parsed?
        self
      end
    end

    def parsed?
      @code&.zero? && @first_dse >= 0
    end

    def error
      if @code&.positive?
        session.error_message(@code)
      end
    end

    private

      attr_reader :native

      # One trip through the shim: parse, compute the first date, render the
      # message in the mode asked for.
      def expand(mode, trigger, timetrig)
        dse = Fiddle::Pointer.malloc(Fiddle::SIZEOF_INT, Fiddle::RUBY_FREE)
        message = Fiddle::Pointer.malloc(Fiddle::SIZEOF_VOIDP, Fiddle::RUBY_FREE)

        code = Session::LOCK.synchronize do
          native.parse_reminder(
            terminated,
            trigger,
            timetrig,
            dse,
            message,
            mode,
          )
        end

        [code, dse[0, Fiddle::SIZEOF_INT].unpack1("i!"), string_at(message).strip]
      end

      def terminated
        Fiddle::Pointer["#{line.chomp}\0"]
      end

      def read_first
        if parsed?
          session.date(@first_dse)
        end
      end

      def first_dse
        @first_dse
      end

      def next_dse(from)
        error_code = Fiddle::Pointer.malloc(Fiddle::SIZEOF_INT, Fiddle::RUBY_FREE)

        Session::LOCK.synchronize do
          native.next_trigger(
            @trigger,
            @timetrig,
            from,
            error_code,
          )
        end
      end

      def type_name
        TYPE_NAMES.keys.find { |name| native.public_send(name) == trigger_field(:typ) }
      end

      def trigger_field(name)
        native.public_send(:"trigger_#{name}", @trigger)
      end

      def timetrig_field(name)
        native.public_send(:"timetrig_#{name}", @timetrig)
      end

      # A field Remind fills with a sentinel when the reminder did not say.
      def field(name, sentinel)
        value = trigger_field(name)

        if value == sentinel
          nil
        else
          value
        end
      end

      def positive(value)
        if value > 0
          value
        end
      end

      def string_at(slot)
        address = slot[0, Fiddle::SIZEOF_VOIDP].unpack1("J")

        if address.zero?
          ""
        else
          Fiddle::Pointer.new(address).to_s.force_encoding(Encoding::UTF_8)
        end
      end
  end
end

__END__

describe "Remind::Reminder" do
  session = Remind::Session.new
  session.today = Date.new(2026, 8, 19)   # a Wednesday

  reminder = proc { |line| Remind::Reminder.parse(line, session: session) }
  dates = proc { |line, count| reminder.(line).occurrences(limit: count).to_a.map(&:to_s) }

  describe "what it will parse" do
    it "parses a reminder" do
      reminder.("REM 15 Jan MSG dentist").should.not.be.nil
    end

    it "parses one with the REM left off, which Remind allows" do
      reminder.("15 Jan MSG dentist").should.not.be.nil
    end

    it "does not parse one of Remind's other commands" do
      reminder.("SET a 1").should.be.nil
      reminder.("IF 1").should.be.nil
      reminder.("OMIT 25 Dec").should.be.nil
      reminder.("# a comment mentioning REM and MSG").should.be.nil
    end

    it "parses a line whose first word Remind does not know, as Remind does" do
      reminder.("15 Jan MSG implicit").first.should == Date.new(2027, 1, 15)
    end

    it "does not parse a reminder with no body" do
      reminder.("REM 15 Jan").should.be.nil
    end

    it "does not parse a trigger that can never fire" do
      reminder.("REM 30 Feb MSG never").should.be.nil
    end
  end

  describe "the fields, as Remind read them" do
    it "reads a day, a month and a year" do
      parsed = reminder.("REM 15 Jan 2027 MSG dentist")

      parsed.day.should == 15
      parsed.month.should == 1
      parsed.year.should == 2027
    end

    it "leaves out what the trigger left out" do
      parsed = reminder.("REM 15 MSG rent")

      parsed.day.should == 15
      parsed.month.should.be.nil
      parsed.year.should.be.nil
    end

    it "reads the weekdays as the RFC spells them" do
      reminder.("REM Mon Wed Fri MSG gym").weekdays.should == %w[MO WE FR]
      reminder.("REM Sun MSG rest").weekdays.should == %w[SU]
    end

    it "reads a repeat interval" do
      reminder.("REM 1 Jan 2027 *14 MSG fortnightly").repeat.should == 14
      reminder.("REM 15 MSG rent").repeat.should.be.nil
    end

    it "reads an UNTIL date" do
      reminder.("REM 1 Jan 2027 *7 UNTIL 1 Mar 2027 MSG weekly").until_date.should ==
        Date.new(2027, 3, 1)
    end

    it "reads advance warning in days" do
      reminder.("REM 15 +3 MSG rent").warning_days.should == 3
    end

    it "reads the AT clause and its alarm" do
      parsed = reminder.("REM Mon AT 9:30 +15 DURATION 1:00 MSG standup")

      parsed.at.should == 570
      parsed.warning_minutes.should == 15
      parsed.duration.should == 60
    end

    it "leaves the duration nil when the reminder gave none" do
      reminder.("REM Mon AT 9:30 MSG standup").duration.should.be.nil
    end

    it "leaves the time nil for an all-day reminder" do
      reminder.("REM 15 Jan MSG dentist").at.should.be.nil
    end

    it "reads a back-count" do
      reminder.("REM 1 -1 MSG last day of the month").back.should == 1
      reminder.("REM 15 MSG rent").back.should.be.nil
    end

    it "knows a reminder that skips OMITted days from one that does not" do
      reminder.("REM 1 Mar SKIP OMIT Sat Sun MSG payday").skip.should.not == 0
      reminder.("REM 1 Mar MSG payday").skip.should == 0
    end
  end

  describe "the message, expanded by Remind" do
    it "reads the message" do
      reminder.("REM 15 Jan MSG dentist").description.should == "dentist"
    end

    it "expands the substitutions against the day it is read on" do
      reminder.("REM 15 +3 MSG rent due %b").description.should.include "in 27 days' time"
    end

    it "reads as of another day when asked to" do
      parsed = reminder.("REM 15 +3 MSG rent due %b").as_of(Date.new(2026, 9, 15))

      parsed.description.should == "rent due today"
      parsed.first.should == Date.new(2026, 9, 15)
    end

    it "puts today back after reading as of another day" do
      reminder.("REM 15 MSG rent").as_of(Date.new(2030, 1, 1))

      session.today.should == Date.new(2026, 8, 19)
    end

    it "gives the whole message when nothing marks a title" do
      reminder.("REM 15 Jan MSG dentist").summary.should == "dentist"
    end

    it "takes the title a reminder marked for a calendar" do
      parsed = reminder.(%q{REM 15 Jan MSG %"dentist%" bring the form})

      parsed.summary.should == "dentist"
      parsed.description.should == "dentist bring the form"
    end
  end

  describe "the type" do
    it "knows a MSG reminder is something a calendar can show" do
      reminder.("REM 15 Jan MSG dentist").display?.should.be.true
    end

    it "knows a RUN reminder is not" do
      parsed = reminder.("REM 15 Jan RUN backup.sh")

      parsed.type.should == :run
      parsed.display?.should.be.false
    end
  end

  describe "the dates, computed by Remind" do
    it "starts at the first date the reminder triggers on" do
      reminder.("REM 15 Jan MSG dentist").first.should == Date.new(2027, 1, 15)
    end

    it "walks a weekly reminder" do
      dates.("REM Mon MSG gym", 3).should == %w[2026-08-24 2026-08-31 2026-09-07]
    end

    it "walks a monthly one" do
      dates.("REM 15 MSG rent", 3).should == %w[2026-09-15 2026-10-15 2026-11-15]
    end

    it "walks a yearly one" do
      dates.("REM 1 Jan MSG new year", 3).should == %w[2027-01-01 2028-01-01 2029-01-01]
    end

    it "reads weekday-and-day the way Remind does, not the way it looks" do
      # The Monday of the week the 1st falls in, not the first Monday.
      dates.("REM Mon 1 MSG first monday", 3).should == %w[2026-09-07 2026-10-05 2026-11-02]
    end

    it "stops a reminder that happens once" do
      dates.("REM 25 Dec 2027 MSG christmas", 5).should == %w[2027-12-25]
    end

    it "stops at UNTIL" do
      dates.("REM 1 Jan 2027 *7 UNTIL 20 Jan 2027 MSG weekly", 9)
           .should == %w[2027-01-01 2027-01-08 2027-01-15]
    end

    it "skips what the reminder says to skip" do
      # 1 March 2031 is a Saturday, and this reminder skips it entirely.
      dates.("REM 1 Mar SKIP OMIT Sat Sun MSG payday", 6)
           .should == %w[2027-03-01 2028-03-01 2029-03-01 2030-03-01 2032-03-01 2033-03-01]
    end

    it "stops where it is told to stop" do
      reminder.("REM Mon MSG gym").occurrences(limit: 2).to_a.length.should == 2
    end
  end
end
