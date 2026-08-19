# frozen_string_literal: true

require "date"
require "fiddle"

require_relative "library"
require_relative "native"
require_relative "runtime"
require_relative "value"

module Remind
  # Remind evaluated something and objected. The message is Remind's own, out
  # of `GetErr`.
  class EvaluationError < Error
    attr_reader :code, :subject

    def initialize(code, message, subject)
      @code = code
      @subject = subject

      super("#{message} in #{subject.inspect}")
    end
  end

  # A live Remind interpreter.
  #
  # Remind is a program, not a library, and it shows in the shape of the C:
  # today's date is a global, the current time is a global, and everything is
  # computed against whatever those say. That has two consequences.
  #
  # The first is a gift: "now" is settable, so a calculation against a fixed
  # date is reproducible rather than a reading off the clock. Converting a
  # reminder file to a calendar depends on it -- `REM Mon` means a different
  # first date tomorrow than it does today.
  #
  # The second is that the state is per-process, not per-object. Two Sessions
  # are two views of the same globals, so the lock is on the class and calls
  # into the library are serialised whether they came from one Session or
  # several.
  class Session
    LOCK = Mutex.new

    NO_TIME = -1

    SECONDS_PER_MINUTE = 60

    attr_reader :native

    def initialize(native: Native.new, diagnostics: false)
      @native = native

      Runtime.boot(native, diagnostics: diagnostics)
    end

    # Evaluates a Remind expression: an Integer for a number, a String for a
    # string, a Date for a date, a Time for a datetime, minutes since midnight
    # for a time.
    #
    #   session.evaluate("moonphase(today())")   # => 46
    #   session.evaluate("version()")            # => "06.02.10"
    def evaluate(expression)
      LOCK.synchronize do
        evaluate_unlocked(expression)
      end
    end

    # The date every relative calculation is relative to.
    def today
      date(native.read_global("DSEToday"))
    end

    # Pins it, the way `remind --date=` does.
    def today=(date)
      LOCK.synchronize do
        pin_date(date)
      end
    end

    # Pins the date and the time of day together, for reminders that depend on
    # the clock as well as the calendar.
    def now=(time)
      LOCK.synchronize do
        pin_date(time.to_date)
        pin_time((time.hour * 60) + time.min)
      end
    end

    def unpin_time
      LOCK.synchronize do
        pin_time(nil)
      end
    end

    # Remind's day count for a date, and back again.
    def dse(date)
      native.dse(date.year, date.month - 1, date.day)
    end

    def date(dse)
      Value.to_date(dse, native)
    end

    # Whether Remind prints its own diagnostics -- the offending line with a
    # caret under it -- as well as this raising.
    def diagnostics=(wanted)
      LOCK.synchronize do
        Runtime.point_errors(native, wanted)
      end
    end

    # The Remind release the library was built from, out of the library's own
    # `version()` rather than out of this gem's idea of it.
    def version
      evaluate("version()")
    end

    def error_message(code)
      native.error_message(code).to_s
    end

    private

      def evaluate_unlocked(expression)
        terminated = "#{expression}\0"
        cursor = pointer_to(terminated)
        result = Value.allocate

        code = native.evaluate(cursor, result, nil)

        if code.zero?
          Value.read(result, native)
        else
          raise EvaluationError.new(code, error_message(code), expression)
        end
      end

      # EvalExpr takes a `char **`: it advances the caller's pointer past what
      # it consumed, so it is given a slot holding the address of the text
      # rather than the text itself.
      def pointer_to(text)
        buffer = Fiddle::Pointer[text]
        slot = Fiddle::Pointer.malloc(Fiddle::SIZEOF_VOIDP, Fiddle::RUBY_FREE)
        slot[0, Fiddle::SIZEOF_VOIDP] = [buffer.to_i].pack("J")

        # The slot keeps an address, which the garbage collector cannot see,
        # so the string it points into has to outlive the call.
        @evaluating = text

        slot
      end

      # RealToday is deliberately left alone: it is what the system clock said
      # when the library came up, and Remind uses it to tell today from a date
      # it was told to pretend about.
      def pin_date(date)
        counted = dse(date)

        native.write_global("DSEToday", counted)
        native.write_global("LocalDSEToday", counted)
        native.write_global("CurYear", date.year)
      end

      def pin_time(minutes)
        if minutes.nil?
          native.write_global("SysTime", NO_TIME)
          native.write_global("LocalSysTime", NO_TIME)
        else
          native.write_global("SysTime", minutes * SECONDS_PER_MINUTE)
          native.write_global("LocalSysTime", minutes * SECONDS_PER_MINUTE)
        end
      end
  end
end

__END__

describe "Remind::Session" do
  session = Remind::Session.new

  before do
    session.today = Date.new(2027, 1, 15)
  end

  describe "evaluate" do
    it "answers an integer" do
      session.evaluate("1 + 2").should == 3
    end

    it "answers a string" do
      session.evaluate('"a" + "b"').should == "ab"
    end

    it "answers a date" do
      session.evaluate("today()").should == Date.new(2027, 1, 15)
    end

    it "answers a time as minutes since midnight" do
      session.evaluate("12:30").should == 750
    end

    it "runs Remind's own functions" do
      session.evaluate("wkdaynum(today())").should == 5
      session.evaluate("trigger(date(2027, 1, 15))").should == "15 January 2027"
    end

    it "reads the version out of the library it loaded" do
      session.version.should == Remind::REMIND_VERSION
    end

    it "raises with Remind's own message when the expression is wrong" do
      error = lambda { session.evaluate("1 +") }.should.raise Remind::EvaluationError

      error.message.should.include "1 +"
      error.code.should.not == 0
    end
  end

  describe "pinning the clock" do
    it "makes today whatever it is told" do
      session.today = Date.new(2030, 6, 1)

      session.today.should == Date.new(2030, 6, 1)
      session.evaluate("today()").should == Date.new(2030, 6, 1)
    end

    it "makes a date calculation reproducible" do
      session.evaluate("today() + 30").should == Date.new(2027, 2, 14)
    end

    it "pins the time of day as well" do
      session.now = Time.local(2027, 1, 15, 9, 30)

      session.evaluate("now()").should == 570
    ensure
      session.unpin_time
    end
  end

  describe "dates" do
    it "converts to Remind's day count and back" do
      session.dse(Date.new(1990, 1, 1)).should == 0
      session.date(0).should == Date.new(1990, 1, 1)
      session.dse(Date.new(2027, 1, 15)).should == 13528
    end
  end
end
