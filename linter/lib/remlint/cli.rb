# frozen_string_literal: true

require "optparse"

require_relative "config"
require_relative "formatter"
require_relative "rules"
require_relative "runner"
require_relative "version"

module RemLint
  # The `remlint` command.
  #
  # Streams are injected rather than assumed, so the whole command is testable
  # without shelling out or capturing `$stdout`.
  class CLI
    EXIT_SUCCESS = 0
    EXIT_OFFENSES = 1
    EXIT_USAGE = 2

    DEFAULT_PATHS = ["."].freeze

    Options = Struct.new(
      :paths,
      :config_path,
      :only,
      :format,
      :fail_level,
      keyword_init: true,
    )

    attr_reader :out, :err

    def initialize(out: $stdout, err: $stderr)
      @out = out
      @err = err
    end

    def call(argv)
      options = Options.new(
        paths:       [],
        config_path: nil,
        only:        nil,
        format:      Formatter::DEFAULT_TEMPLATE,
        fail_level:  "warning",
      )

      dispatch(parse(argv, options), options)
    rescue OptionParser::ParseError => error
      err.puts(error.message)
      EXIT_USAGE
    end

    private

      # `parse` returns a symbol for the flags that do something instead of
      # linting, and nil for an ordinary run.
      def dispatch(action, options)
        case action
        when :version     then print_version
        when :help        then EXIT_SUCCESS
        when :show_rules  then print_rules
        when :show_config then print_config(options)
        else lint(options)
        end
      end

      def parse(argv, options)
        action = nil

        parser(options) { |chosen| action = chosen }.parse!(argv)
        options.paths = paths_from(argv)

        action
      end

      # No paths means the working directory, the way every other linter reads
      # a bare invocation.
      def paths_from(argv)
        if argv.empty?
          DEFAULT_PATHS.dup
        else
          argv
        end
      end

      def parser(options)
        OptionParser.new do |parser|
          parser.banner = "Usage: remlint [options] [path...]"

          parser.on("-c", "--config PATH", "Configuration file (default: nearest .remlint.yml)") do |path|
            options.config_path = path
          end

          parser.on(
            "-o",
            "--only RULES",
            Array,
            "Run only these rules",
          ) do |rules|
            options.only = rules
          end

          parser.on("-f", "--format TEMPLATE", "Output template with %{path} %{line} %{column} %{severity} %{rule} %{message}") do |template|
            options.format = template
          end

          parser.on("--fail-level LEVEL", SEVERITIES, "Exit non-zero at this severity or worse (default: warning)") do |level|
            options.fail_level = level
          end

          parser.on("--show-rules", "List the rules and whether they are on") { yield :show_rules }
          parser.on("--show-config", "Print the configuration in effect") { yield :show_config }
          parser.on("-v", "--version", "Print the version") { yield :version }

          parser.on("-h", "--help", "Print this message") do
            out.puts(parser.help)
            yield :help
          end
        end
      end

      def lint(options)
        config = resolve_config(options)
        offenses = Runner.new(config).run(options.paths)

        out.print(Formatter.new(template: options.format).render(offenses))

        exit_code(offenses, options.fail_level)
      end

      def resolve_config(options)
        base = base_config(options)

        if options.only
          base.only(options.only)
        else
          base
        end
      end

      def base_config(options)
        if options.config_path
          Config.load_file(options.config_path)
        else
          Config.discover
        end
      end

      # Offences below the threshold are reported and do not fail the run, so a
      # project can adopt the informational rules without turning its build red.
      def exit_code(offenses, fail_level)
        if offenses.any? { |offense| offense.at_least?(fail_level) }
          EXIT_OFFENSES
        else
          EXIT_SUCCESS
        end
      end

      def print_version
        out.puts("remlint #{VERSION}")
        EXIT_SUCCESS
      end

      def print_rules
        config = Config.discover

        Rule.all.sort_by(&:rule_name).each do |rule|
          if config.enabled?(rule)
            state = "on "
          else
            state = "off"
          end

          out.puts("#{state}  #{rule.rule_name.ljust(26)} #{rule.description}")
        end

        EXIT_SUCCESS
      end

      def print_config(options)
        out.puts(YAML.dump(resolve_config(options).settings))
        EXIT_SUCCESS
      end
  end
end

__END__

require "stringio"
require "tempfile"

describe "RemLint::CLI" do
  run = proc do |argv|
    out = StringIO.new
    err = StringIO.new
    status = RemLint::CLI.new(out: out, err: err).call(argv)

    { status: status, out: out.string, err: err.string }
  end

  # The Tempfile objects are kept, not just their paths: an unreferenced
  # Tempfile is garbage, and its finalizer unlinks the file. In a short run
  # nothing collects and the specs pass; in a long one the file vanishes
  # between being written and being linted.
  fixtures = []

  fixture = proc do |text|
    file = Tempfile.new(["remlint-cli", ".rem"])
    file.write(text)
    file.close
    fixtures << file
    file.path
  end

  describe "linting" do
    it "prints nothing and exits zero for a clean file" do
      result = run.([fixture.("MSG hi\n")])

      result[:status].should == 0
      result[:out].should == ""
    end

    it "prints each offence and exits non-zero" do
      result = run.(["--only", "TrailingWhitespace", fixture.("MSG hi \n")])

      result[:status].should == 1
      result[:out].should.match(/: error: \[TrailingWhitespace\] Trailing whitespace/)
    end

    it "runs only the rules --only names" do
      result = run.(["--only", "LineLength", fixture.("MSG hi \n")])

      result[:status].should == 0
    end

    it "honours a custom output format" do
      result = run.(["--only", "TrailingWhitespace", "--format", "%{line}|%{rule}", fixture.("MSG hi \n")])

      result[:out].should.match(/\A1\|TrailingWhitespace\n/)
    end
  end

  describe "--fail-level" do
    it "fails on an offence at the threshold" do
      result = run.(["--only", "TrailingWhitespace", "--fail-level", "error", fixture.("MSG hi \n")])

      result[:status].should == 1
    end

    it "reports an offence below the threshold without failing on it" do
      path = fixture.("#{'x' * 200}\n")
      result = run.(["--only", "LineLength", "--fail-level", "error", path])

      result[:status].should == 0
      result[:out].should.match(/\[LineLength\]/)
    end
  end

  describe "informational flags" do
    it "prints the version" do
      result = run.(["--version"])

      result[:status].should == 0
      result[:out].should == "remlint #{RemLint::VERSION}\n"
    end

    it "lists the rules and whether each is on" do
      result = run.(["--show-rules"])

      result[:status].should == 0
      result[:out].should.match(/^on   TrailingWhitespace/)
    end

    it "prints the configuration in effect" do
      run.(["--show-config"])[:out].should.match(/TrailingWhitespace/)
    end

    it "prints usage for --help and exits zero" do
      result = run.(["--help"])

      result[:status].should == 0
      result[:out].should.match(/Usage: remlint/)
    end
  end

  describe "bad usage" do
    it "reports an unknown flag on stderr and exits two" do
      result = run.(["--nonsense"])

      result[:status].should == 2
      result[:err].should.match(/invalid option/)
    end

    it "reports an unknown --fail-level" do
      run.(["--fail-level", "catastrophic"])[:status].should == 2
    end
  end
end
