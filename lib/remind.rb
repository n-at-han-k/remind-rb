# frozen_string_literal: true

require_relative "remind/builder"
require_relative "remind/library"
require_relative "remind/native"
require_relative "remind/reminder"
require_relative "remind/runtime"
require_relative "remind/session"
require_relative "remind/source"
require_relative "remind/value"
require_relative "remind/version"

# Ruby bindings for Remind, through Fiddle.
#
# Remind is a calendar program, and underneath the calendar is an interpreter:
# an expression language with dates as a first-class type, and a trigger
# language that says things like "the Monday of the week the 13th falls in,
# unless that is a holiday, in which case the day before". The usual way to
# reach any of that from another language is to shell out to `remind` and
# parse what comes back.
#
# These bindings call the C instead, and the reason to is `Remind::Reminder`.
# Every program that has read a reminder file with regular expressions has got
# part of the trigger language wrong -- there is a lot of it, and Remind's
# manual describes eighteen worked examples before it gets to the exceptions.
# Here, `ParseRem` parses the trigger, `ComputeTrigger` says which dates it
# fires on, and `DoSubst` renders the message for each of them. Nothing about
# the language is interpreted on this side.
#
#   Remind.today = Date.new(2026, 8, 19)
#
#   reminder = Remind.parse("REM Mon 13 SKIP OMIT Sat MSG payday")
#   reminder.summary                      # => "payday"
#   reminder.occurrences.first(3)         # => Remind's own dates
#
#   Remind.evaluate("moonphase(today())") # => 46
#
# == Why Fiddle, and not a C extension
#
# There is nothing to extend. Remind's sources compile into a shared library
# unchanged -- `Builder` does it with the flags `./configure` already chose --
# and everything worth calling is a plain function over ints and pointers.
# The one C file in this gem, `ext/shim.c`, is there for struct layout and for
# the sequence of six calls that parses a REM line; not because Fiddle needed
# help calling anything.
#
# == The state
#
# Remind keeps "today" in a global, because a program that runs once and exits
# has no reason not to. So `Remind.today =` moves the ground under every
# calculation -- deliberately, because a reminder that says `Mon` means a
# different date tomorrow than it does today, and pinning the date is what
# makes a conversion reproducible.
module Remind
  class << self
    # The process-wide interpreter: there is one set of globals to talk to, so
    # there is one of these.
    def session
      @session ||= Session.new
    end

    attr_writer :session

    # One REM line, or nil if the line is not a reminder.
    def parse(line)
      Reminder.parse(line, session: session)
    end

    # Every reminder in a file, with continuations joined and INCLUDEs
    # followed, as Remind reads them.
    def read(path)
      Source.new(path, session: session).reminders
    end

    def evaluate(expression)
      session.evaluate(expression)
    end

    def today
      session.today
    end

    def today=(date)
      session.today = date
    end

    def now=(time)
      session.now = time
    end

    def dse(date)
      session.dse(date)
    end

    def date(dse)
      session.date(dse)
    end

    # The Remind release the library was built from.
    def version
      session.version
    end

    def library_path
      Library.path
    end
  end
end

__END__

describe "Remind" do
  before do
    Remind.today = Date.new(2026, 8, 19)
  end

  it "evaluates an expression through the default session" do
    Remind.evaluate("1 + 1").should == 2
  end

  it "binds the version it vendors" do
    Remind.version.should == Remind::REMIND_VERSION
  end

  it "shares one interpreter, because there is one set of globals" do
    Remind.session.should.be.same_as Remind.session
  end

  it "parses a reminder" do
    Remind.parse("REM Mon MSG gym").first.should == Date.new(2026, 8, 24)
  end

  it "answers nil for a line that is not one" do
    Remind.parse("SET a 1").should.be.nil
  end

  it "moves every calculation when today moves" do
    Remind.today = Date.new(2027, 12, 25)

    Remind.parse("REM Mon MSG gym").first.should == Date.new(2027, 12, 27)
  end

  it "converts dates the way Remind counts them" do
    Remind.dse(Date.new(1990, 1, 1)).should == 0
    Remind.date(13528).should == Date.new(2027, 1, 15)
  end
end
