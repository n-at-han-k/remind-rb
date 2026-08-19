# frozen_string_literal: true

require "date"
require "optparse"

require_relative "converter"
require_relative "recurrence"
require_relative "version"

module Rem2ics
  # The `rem2ics` command.
  #
  # Streams are injected rather than assumed, so the whole command is testable
  # without shelling out or capturing `$stdout`.
  class CLI
    EXIT_SUCCESS = 0
    EXIT_FAILURE = 1
    EXIT_USAGE = 2

    # Remind reads standard input under this name; so does this.
    STDIN = "-"

    Options = Struct.new(
      :paths,
      :today,
      :horizon,
      :organizer,
      keyword_init: true,
    )

    attr_reader :out, :err

    def initialize(out: $stdout, err: $stderr)
      @out = out
      @err = err
    end

    def call(argv)
      options = Options.new(
        paths:     [],
        today:     Date.today,
        horizon:   Recurrence::DEFAULT_HORIZON,
        organizer: nil,
      )

      dispatch(parse(argv, options), options)
    rescue OptionParser::ParseError, Date::Error => error
      err.puts(error.message)
      EXIT_USAGE
    end

    private

      def dispatch(action, options)
        case action
        when :version then print_version
        when :help    then EXIT_SUCCESS
        else convert(options)
        end
      end

      def convert(options)
        out.print(calendar(options).to_ical)

        EXIT_SUCCESS
      rescue Remind::LibraryMissing => error
        err.puts(error.message)
        EXIT_FAILURE
      end

      def calendar(options)
        Converter.new(
          horizon:   options.horizon,
          organizer: options.organizer,
          warnings:  err,
        ).call(options.paths, today: options.today)
      end

      def parse(argv, options)
        action = nil

        parser(options) { |chosen| action = chosen }.parse!(argv)
        options.paths = paths_from(argv)

        action
      end

      # No files means standard input, the way `remind -` does.
      def paths_from(argv)
        if argv.empty?
          [STDIN]
        else
          argv
        end
      end

      def parser(options)
        OptionParser.new do |parser|
          parser.banner = "Usage: rem2ics [options] [file...]"

          parser.on("-d", "--date DATE", "Convert as of this date (default: today)") do |date|
            options.today = Date.parse(date)
          end

          parser.on(
            "-n",
            "--horizon COUNT",
            Integer,
            "How many occurrences to check a recurrence rule against (default: #{Recurrence::DEFAULT_HORIZON})",
          ) do |count|
            options.horizon = count
          end

          parser.on("-o", "--organizer ADDRESS", "ORGANIZER for every event") do |address|
            options.organizer = address
          end

          parser.on("-v", "--version", "Print the version") { yield :version }

          parser.on("-h", "--help", "Print this message") do
            out.puts(parser.help)
            yield :help
          end
        end
      end

      def print_version
        out.puts("rem2ics #{VERSION} (Remind #{Remind.version})")

        EXIT_SUCCESS
      end
  end
end

__END__

require "stringio"
require "tempfile"

describe "Rem2ics::CLI" do
  run = proc do |argv|
    out = StringIO.new
    err = StringIO.new
    code = Rem2ics::CLI.new(out: out, err: err).call(argv)

    [code, out.string, err.string]
  end

  file = proc do |text|
    handle = Tempfile.new(["reminders", ".rem"])
    handle.write(text)
    handle.close
    handle.path
  end

  it "converts the files it is given" do
    code, output, = run.(["--date", "2026-08-19", file.("REM 25 Dec MSG christmas\n")])

    code.should == 0
    output.should.include "SUMMARY:christmas"
  end

  it "converts as of the date it is told" do
    _, output, = run.(["--date", "2027-03-01", file.("REM Mon MSG gym\n")])

    output.should.include "DTSTART;VALUE=DATE:20270301"
  end

  it "takes the organizer from the command line" do
    _, output, = run.(["-o", "me@host", file.("REM 25 Dec MSG christmas\n")])

    output.should.include "ORGANIZER:mailto:me@host"
  end

  it "prints the version of both itself and Remind" do
    code, output, = run.(["--version"])

    code.should == 0
    output.should.include Rem2ics::VERSION
    output.should.include Remind.version
  end

  it "prints help without converting anything" do
    code, output, = run.(["--help"])

    code.should == 0
    output.should.include "Usage: rem2ics"
    output.should.not.include "BEGIN:VCALENDAR"
  end

  it "rejects an option it does not know" do
    code, _, errors = run.(["--nonsense"])

    code.should == 2
    errors.should.include "nonsense"
  end

  it "rejects a date it cannot read" do
    run.(["--date", "not-a-date"]).first.should == 2
  end
end
