# frozen_string_literal: true

require_relative "native"

module Remind
  # The startup Remind does before it looks at its command line.
  #
  # `InitRemind` is one function with two jobs: it brings the interpreter up
  # -- hash tables, dynamic buffers, the translation table, today's date --
  # and then it parses argv, opens files and, on bad input, exits the process.
  # A library wants the first job and never the second, so this repeats the
  # first rather than calling the function that does both.
  #
  # Skipping it is not an option. Remind's tables are static storage with null
  # function pointers in them until something initialises them, so the first
  # expression that takes an error path -- where `GetErr` translates the
  # message -- walks into a null pointer and takes the process with it.
  #
  # It runs once per process, because the state is process-wide.
  module Runtime
    LOCK = Mutex.new

    # In the order InitRemind does them.
    TABLES = %i[
      init_variables
      init_user_functions
      init_translation_table
      init_files
      init_dedupe_table
    ].freeze

    # Remind reports a parse error by printing the line with a caret under the
    # offending character. A library raises instead, so by default the
    # printing goes nowhere and the exception carries the message; a caller
    # who wants the caret can ask for it.
    DEVNULL = "/dev/null"

    module_function

    def booted
      @booted ||= {}
    end

    def boot(native, diagnostics: false)
      LOCK.synchronize do
        if booted[native.path]
          false
        else
          start(native, diagnostics)
        end
      end
    end

    def start(native, diagnostics)
      point_errors(native, diagnostics)
      TABLES.each { |name| native.public_send(name) }
      Native::BUFFERS.each { |name| native.init_buffer(native.address_of(name)) }
      read_the_clock(native)

      booted[native.path] = true
    end

    # ErrFp starts as a null FILE *, and main() is what points it at stderr.
    # Everything that reports an error writes through it, including the paths
    # that would otherwise dereference the null.
    def point_errors(native, diagnostics)
      if diagnostics
        native.write_pointer(Native::ERROR_STREAM, native.standard_error)
      else
        native.write_pointer(Native::ERROR_STREAM, discard(native))
      end
    end

    # One stream per process, held open: reopening it per expression would
    # leak a descriptor every time.
    def discard(native)
      @discard ||= native.open_stream(
        Fiddle::Pointer["#{DEVNULL}\0"],
        Fiddle::Pointer["w\0"],
      ).to_i
    end

    # SystemDate answers today as a day count and fills in the year, month and
    # day Remind completes partial dates with.
    def read_the_clock(native)
      year = Fiddle::Pointer.malloc(Fiddle::SIZEOF_INT, Fiddle::RUBY_FREE)
      month = Fiddle::Pointer.malloc(Fiddle::SIZEOF_INT, Fiddle::RUBY_FREE)
      day = Fiddle::Pointer.malloc(Fiddle::SIZEOF_INT, Fiddle::RUBY_FREE)
      today = native.system_date(year, month, day)

      native.write_global("RealToday", today)
      native.write_global("DSEToday", today)
      native.write_global("LocalDSEToday", today)
      native.write_global("CurYear", year[0, Fiddle::SIZEOF_INT].unpack1("i!"))
      native.write_global("LocalSysTime", native.system_time(0))
    end
  end
end

__END__

require_relative "session"

describe "Remind::Runtime" do
  native = Remind::Native.new

  it "has booted by the time a session exists" do
    Remind::Session.new

    Remind::Runtime.booted[native.path].should.be.true
  end

  it "boots once per library, not once per caller" do
    Remind::Session.new

    Remind::Runtime.boot(native).should.be.false
  end

  it "leaves RealToday reading off the system clock" do
    Remind::Session.new

    native.read_global("RealToday").should == native.dse(Date.today.year, Date.today.month - 1, Date.today.day)
  end

  it "survives the error path a null translation table would crash on" do
    session = Remind::Session.new

    lambda { session.evaluate("1 +") }.should.raise Remind::EvaluationError
  end
end
