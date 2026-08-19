# frozen_string_literal: true

require "fiddle"

require_relative "native"
require_relative "reminder"
require_relative "session"

module Remind
  # A file of reminders, read by Remind.
  #
  # Named Source rather than File because it lives inside `Remind`, where a
  # class called File would shadow the one in the standard library for every
  # other file in the gem.
  #
  # A reminder file is not a list of lines. A backslash joins two of them into
  # one; `INCLUDE` splices another file into the middle; `INCLUDEsys` reaches
  # into the system directory for the holiday files that ship with Remind. Any
  # reader that treats the file as text gets all three wrong, so this one does
  # not read text: `IncludeFile` opens the file and `ReadLine` hands back one
  # logical line at a time, out of whichever file is currently on Remind's
  # stack, exactly as `remind` itself sees them.
  #
  # What comes out is the lines Remind can turn into events. Everything else
  # -- SET, IF, OMIT, comments, RUN reminders -- is skipped, because it is a
  # command rather than an appointment.
  class Source
    # Remind reads standard input under this name, the same as the program.
    STDIN = "-"

    attr_reader :path, :session

    def initialize(path, session: Session.new)
      @path = path
      @session = session
    end

    # Every reminder in the file, in the order the file gives them. Lazy: a
    # file can INCLUDE another, and a caller that only wants the first few
    # should not pay for the rest.
    def reminders
      Enumerator.new do |found|
        lines.each do |line|
          reminder = Reminder.parse(line, session: session)

          if reminder
            found << reminder
          end
        end
      end
    end

    # The logical lines, continuations joined and includes spliced.
    def lines
      Enumerator.new do |line|
        open

        while (text = read)
          line << text
        end
      end
    end

    private

      def native
        session.native
      end

      def open
        code = native.open_file(Fiddle::Pointer["#{path}\0"])

        if code.nonzero?
          raise EvaluationError.new(code, session.error_message(code), path)
        end
      end

      # nil at the end of the last file, which is how the enumerator stops.
      def read
        slot = Fiddle::Pointer.malloc(Fiddle::SIZEOF_VOIDP, Fiddle::RUBY_FREE)
        code = native.read_line(slot)

        if code.zero?
          text_at(slot)
        end
      end

      def text_at(slot)
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

require "tempfile"

describe "Remind::Source" do
  session = Remind::Session.new
  session.today = Date.new(2026, 8, 19)

  written = proc do |text|
    file = Tempfile.new(["reminders", ".rem"])
    file.write(text)
    file.close
    Remind::Source.new(file.path, session: session)
  end

  it "reads the reminders in a file" do
    file = written.(<<~REM)
      # A comment
      REM 15 Jan MSG dentist
      REM Mon MSG gym
    REM

    file.reminders.map(&:summary).should == ["dentist", "gym"]
  end

  it "joins a continued line, the way Remind does" do
    file = written.(<<~REM)
      REM 15 Jan \\
      MSG dentist
    REM

    file.reminders.map(&:summary).should == ["dentist"]
  end

  it "skips the commands that are not reminders" do
    file = written.(<<~REM)
      SET a 1
      OMIT 25 Dec
      IF a > 0
      REM 1 Jan MSG new year
      ENDIF
    REM

    file.reminders.map(&:summary).should == ["new year"]
  end

  it "splices in an included file" do
    included = Tempfile.new(["included", ".rem"])
    included.write("REM 4 Jul MSG fireworks\n")
    included.close

    file = written.("REM 1 Jan MSG new year\nINCLUDE #{included.path}\n")

    file.reminders.map(&:summary).should == ["new year", "fireworks"]
  end

  it "raises when the file is not there" do
    lambda { Remind::Source.new("/nonexistent.rem", session: session).lines.to_a }
      .should.raise Remind::EvaluationError
  end
end
