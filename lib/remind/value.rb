# frozen_string_literal: true

require "date"
require "fiddle"

module Remind
  # Remind's `Value` -- a type tag and a union of `char *` and `int` -- read
  # back into Ruby.
  #
  #   typedef struct {
  #       char type;
  #       union { char *str; int val; } v;
  #   } Value;
  #
  # This one struct is read directly rather than through the shim: it is two
  # fields, the union sits at the pointer's alignment on every platform
  # Fiddle runs on, and an expression's result is the only place it appears.
  #
  # Every type but one maps onto something already in the standard library.
  # The exception is TIME, which Remind stores as minutes since midnight with
  # no date attached; it stays an Integer, because inventing a date for it
  # would be inventing information.
  module Value
    ERR = 0x0

    INT = 0x1

    TIME = 0x2

    DATE = 0x4

    DATETIME = TIME | DATE

    STR = 0x8

    MINUTES_PER_DAY = 1440

    MINUTES_PER_HOUR = 60

    UNION_OFFSET = Fiddle::SIZEOF_VOIDP

    SIZE = Fiddle::SIZEOF_VOIDP * 2

    module_function

    def allocate
      Fiddle::Pointer.malloc(SIZE, Fiddle::RUBY_FREE)
    end

    def type(pointer)
      pointer[0, 1].unpack1("c")
    end

    # `native` is what turns a day count back into a date: Remind's own
    # FromDSE, so the epoch is Remind's rather than one repeated here.
    def read(pointer, native)
      case type(pointer)
      when INT      then integer(pointer)
      when STR      then string(pointer)
      when DATE     then to_date(integer(pointer), native)
      when TIME     then integer(pointer)
      when DATETIME then to_time(integer(pointer), native)
      end
    end

    def integer(pointer)
      pointer[UNION_OFFSET, Fiddle::SIZEOF_INT].unpack1("i!")
    end

    # The string was malloc'd by Remind and is ours to free once copied.
    def string(pointer)
      address = pointer[UNION_OFFSET, Fiddle::SIZEOF_VOIDP].unpack1("J")

      if address.zero?
        ""
      else
        copied(address)
      end
    end

    def copied(address)
      Fiddle::Pointer.new(address).to_s.force_encoding(Encoding::UTF_8).tap do
        Fiddle.free(address)
      end
    end

    def to_date(dse, native)
      year = Fiddle::Pointer.malloc(Fiddle::SIZEOF_INT, Fiddle::RUBY_FREE)
      month = Fiddle::Pointer.malloc(Fiddle::SIZEOF_INT, Fiddle::RUBY_FREE)
      day = Fiddle::Pointer.malloc(Fiddle::SIZEOF_INT, Fiddle::RUBY_FREE)

      native.from_dse(
        dse,
        year,
        month,
        day,
      )

      # Remind numbers months from zero, everywhere. That stops here.
      Date.new(
        unpack(year),
        unpack(month) + 1,
        unpack(day),
      )
    end

    # A datetime is one number: the day count times the minutes in a day, plus
    # the minutes into that day. It is wall-clock time in the local zone,
    # which is what Time.local means.
    def to_time(packed, native)
      day = to_date(packed / MINUTES_PER_DAY, native)
      minutes = packed % MINUTES_PER_DAY

      Time.local(
        day.year,
        day.month,
        day.day,
        minutes / MINUTES_PER_HOUR,
        minutes % MINUTES_PER_HOUR,
      )
    end

    def unpack(pointer)
      pointer[0, Fiddle::SIZEOF_INT].unpack1("i!")
    end
  end
end

__END__

require_relative "native"

describe "Remind::Value" do
  native = Remind::Native.new

  # Building a Value by hand is the only way to read one without evaluating an
  # expression, and it pins the layout this file assumes.
  build = proc do |type, number|
    Remind::Value.allocate.tap do |pointer|
      pointer[0, 1] = [type].pack("c")
      pointer[Remind::Value::UNION_OFFSET, Fiddle::SIZEOF_INT] = [number].pack("i!")
    end
  end

  read = proc { |type, number| Remind::Value.read(build.(type, number), native) }

  it "reads an integer" do
    read.(Remind::Value::INT, 42).should == 42
    read.(Remind::Value::INT, -17).should == -17
  end

  it "reads a date through Remind's own epoch" do
    read.(Remind::Value::DATE, 0).should == Date.new(1990, 1, 1)
    read.(Remind::Value::DATE, 13528).should == Date.new(2027, 1, 15)
  end

  it "reads a time as minutes since midnight" do
    read.(Remind::Value::TIME, 570).should == 570
  end

  it "reads a datetime as local wall-clock time" do
    packed = (13528 * Remind::Value::MINUTES_PER_DAY) + 570

    read.(Remind::Value::DATETIME, packed).should == Time.local(2027, 1, 15, 9, 30)
  end

  it "reads an error value as nothing at all" do
    read.(Remind::Value::ERR, 0).should.be.nil
  end
end
