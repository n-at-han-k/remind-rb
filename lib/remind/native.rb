# frozen_string_literal: true

require "fiddle"

require_relative "library"

module Remind
  # The dlopen'd library: the Remind functions the bindings call, the shim
  # functions that reach what Fiddle cannot, and the globals Remind keeps its
  # state in.
  #
  # Fiddle rather than a C extension, because there is no extension to write.
  # Remind's sources build into a shared library as they are, and everything
  # here is a plain C function over ints and pointers. The one file of C in
  # this gem, ext/shim.c, exists for struct layout and for the six-call
  # sequence that parses a REM line -- not because Fiddle needs help calling
  # anything.
  #
  # Functions are looked up on first call and kept: `Fiddle::Handle#[]` is a
  # dlsym every time.
  class Native
    INT = Fiddle::TYPE_INT

    POINTER = Fiddle::TYPE_VOIDP

    SIZE = Fiddle::TYPE_SIZE_T

    VOID = Fiddle::TYPE_VOID

    # name => [C symbol, argument types, return type]
    FUNCTIONS = {
      # Dates. Remind counts days from 1990-01-01 and numbers months from
      # zero; both conversions are called rather than repeated, so the epoch
      # cannot drift from the library's.
      dse:                    ["DSE", [INT, INT, INT], INT],
      from_dse:               ["FromDSE", [INT, POINTER, POINTER, POINTER], VOID],

      # Expressions, and the messages for when they fail.
      evaluate:               ["EvalExpr", [POINTER, POINTER, POINTER], INT],
      error_message:          ["GetErr", [INT], POINTER],

      # The startup sequence `Runtime` mirrors. Remind does all of this inside
      # InitRemind, which also parses argv, opens files and exits on bad
      # input, and is therefore not something a library can call.
      init_variables:         ["InitVars", [], VOID],
      init_user_functions:    ["InitUserFunctions", [], VOID],
      init_translation_table: ["InitTranslationTable", [], VOID],
      init_files:             ["InitFiles", [], VOID],
      init_dedupe_table:      ["InitDedupeTable", [], VOID],
      init_buffer:            ["DBufInit", [POINTER], VOID],
      system_date:            ["SystemDate", [POINTER, POINTER, POINTER], INT],
      system_time:            ["SystemTime", [INT], INT],

      # libc's, through the same handle: Remind writes its diagnostics through
      # a FILE *, so somewhere to point it is part of the interface.
      open_stream:            ["fopen", [POINTER, POINTER], POINTER],

      # The shim.
      sizeof_trigger:         ["remrb_sizeof_trigger", [], SIZE],
      sizeof_timetrig:        ["remrb_sizeof_timetrig", [], SIZE],
      parse_reminder:         ["remrb_parse_reminder", [POINTER, POINTER, POINTER, POINTER, POINTER, INT], INT],
      next_trigger:           ["remrb_next_trigger", [POINTER, POINTER, INT, POINTER], INT],
      free_trigger:           ["remrb_free_trigger", [POINTER], VOID],
      open_file:              ["remrb_open_file", [POINTER], INT],
      read_line:              ["remrb_read_line", [POINTER], INT],
      trigger_tags:           ["remrb_trigger_tags", [POINTER], POINTER],
      trigger_timezone:       ["remrb_trigger_timezone", [POINTER], POINTER],
    }.freeze

    # The Trigger fields a calendar entry is made out of. Each is an accessor
    # in the shim, compiled against Remind's own headers, so no byte offset is
    # ever written down on this side.
    TRIGGER_FIELDS = %i[
      wd d m y back delta rep localomit skip until typ once scanfrom from
      priority duration_days eventduration eventstart is_todo addomit need_wkday
    ].freeze

    TIMETRIG_FIELDS = %i[time delta repeat duration].freeze

    # The values Remind uses for "the reminder did not say", and the constants
    # it tags a body with. Read from the shim rather than copied, for the same
    # reason as the field offsets.
    CONSTANTS = %i[
      no_day no_month no_year no_weekday no_until no_time quote_marker
      normal_mode cal_mode eof
      msg_type msf_type run_type cal_type sat_type passthru_type
    ].freeze

    # Remind keeps its idea of now in globals rather than passing it around,
    # so these are as much a part of the interface as the functions.
    #
    #   DSEToday       the date every relative calculation is relative to
    #   LocalDSEToday  the same, before a --date override moves it
    #   RealToday      what the system clock said at startup
    #   CurYear        the year an incomplete date is completed with
    #   SysTime        seconds since midnight, or -1 to read the clock
    GLOBALS = %w[DSEToday LocalDSEToday RealToday CurYear SysTime LocalSysTime].freeze

    # The dynamic buffers Remind expects to have been initialised, and the
    # stream it expects to have been pointed somewhere.
    BUFFERS = %w[Banner LineBuffer ExprBuf].freeze

    ERROR_STREAM = "ErrFp"

    attr_reader :path

    def initialize(path = Library.path)
      @path = path
      @handle = Fiddle::Handle.new(path)
      @functions = {}
    end

    FUNCTIONS.each do |name, (symbol, arguments, returning)|
      define_method(name) do |*values|
        function(symbol, arguments, returning).call(*values)
      end
    end

    TRIGGER_FIELDS.each do |field|
      define_method(:"trigger_#{field}") do |trigger|
        function("remrb_trigger_#{field}", [POINTER], INT).call(trigger)
      end
    end

    TIMETRIG_FIELDS.each do |field|
      define_method(:"timetrig_#{field}") do |timetrig|
        function("remrb_timetrig_#{field}", [POINTER], INT).call(timetrig)
      end
    end

    CONSTANTS.each do |name|
      define_method(name) do
        function("remrb_#{name}", [], INT).call
      end
    end

    def read_global(name)
      global(name)[0, Fiddle::SIZEOF_INT].unpack1("i!")
    end

    def write_global(name, value)
      global(name)[0, Fiddle::SIZEOF_INT] = [value].pack("i!")
    end

    # The address of a global, for the functions that take one: DBufInit wants
    # the buffer itself, not a copy of it.
    def address_of(name)
      Fiddle::Pointer.new(@handle[name])
    end

    # A pointer-sized global, which is what a FILE * is.
    def write_pointer(name, address)
      Fiddle::Pointer.new(@handle[name], Fiddle::SIZEOF_VOIDP)[0, Fiddle::SIZEOF_VOIDP] =
        [address].pack("J")
    end

    # `stderr` is a variable in libc, and it holds the FILE * rather than
    # being one.
    def standard_error
      Fiddle::Pointer.new(Fiddle::Handle::DEFAULT["stderr"], Fiddle::SIZEOF_VOIDP)[
        0,
        Fiddle::SIZEOF_VOIDP,
      ].unpack1("J")
    end

    private

      def function(symbol, arguments, returning)
        @functions[symbol] ||= Fiddle::Function.new(
          @handle[symbol],
          arguments,
          returning,
          name: symbol,
        )
      end

      def global(name)
        Fiddle::Pointer.new(@handle[name], Fiddle::SIZEOF_INT)
      end
  end
end

__END__

describe "Remind::Native" do
  native = Remind::Native.new

  it "loads the library the bindings resolved" do
    native.path.should == Remind::Library.path
  end

  describe "Remind's own functions" do
    it "converts a date to Remind's day count" do
      # Remind counts from 1990-01-01 and numbers months from zero.
      native.dse(1990, 0, 1).should == 0
      native.dse(2027, 0, 15).should == 13528
    end

    it "keeps a function across calls rather than dlsym-ing again" do
      first = native.send(:function, "DSE", [Remind::Native::INT] * 3, Remind::Native::INT)

      native.send(:function, "DSE", [Remind::Native::INT] * 3, Remind::Native::INT)
            .should.be.same_as first
    end
  end

  describe "the shim" do
    it "answers how big the structs a caller has to allocate are" do
      native.sizeof_trigger.should.be > 0
      native.sizeof_timetrig.should.be > 0
    end

    it "answers Remind's sentinels rather than repeating their values" do
      native.no_day.should == -1
      native.no_year.should == -1
      native.no_time.should == 2_147_483_647
    end

    it "answers the body types" do
      native.msg_type.should == 1
      native.run_type.should == 2
    end

    it "answers the marker DoSubst leaves around a calendar title" do
      native.quote_marker.should == 1
    end

    it "has an accessor for every Trigger field the bindings read" do
      Remind::Native::TRIGGER_FIELDS.each do |field|
        native.should.respond_to :"trigger_#{field}"
      end
    end
  end

  describe "globals" do
    it "reads and writes Remind's idea of today" do
      was = native.read_global("DSEToday")

      native.write_global("DSEToday", 13528)
      native.read_global("DSEToday").should == 13528
    ensure
      native.write_global("DSEToday", was)
    end

    it "names every global the bindings touch" do
      Remind::Native::GLOBALS.each do |name|
        lambda { native.read_global(name) }.should.not.raise Fiddle::DLError
      end
    end

    it "finds the buffers Remind expects initialised" do
      Remind::Native::BUFFERS.each do |name|
        native.address_of(name).to_i.should.not == 0
      end
    end
  end
end
