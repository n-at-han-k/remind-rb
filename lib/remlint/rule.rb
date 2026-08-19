# frozen_string_literal: true

require_relative "offense"

module RemLint
  # Base class for rules. Subclassing registers.
  #
  # A rule implements `check` and calls `offend` for each thing it finds. It
  # gets one {Document} and its own slice of configuration, and it is
  # instantiated fresh per document, so a rule accumulating state across a file
  # (block stacks, FSET definitions) does not have to clean up after itself.
  #
  # Registry-by-inheritance rather than an explicit list, following haml-lint:
  # a new file under `rules/` that is required is a rule that runs, with
  # nothing else to remember to edit.
  class Rule
    # Guarded, not plain: `scampi` runs each file's co-located specs by
    # `load`ing the file, which re-executes its top level. An unguarded
    # `REGISTRY = []` would empty the registry halfway through a run and take
    # every already-registered rule with it -- the subclasses are not
    # re-registered, because reopening a class does not call `inherited` again.
    unless defined?(REGISTRY)
      REGISTRY = []
    end

    class << self
      def inherited(subclass)
        super
        REGISTRY << subclass
      end

      # `RemLint::Rules::TrailingWhitespace` configures and reports as
      # `TrailingWhitespace`. Anonymous subclasses -- which specs make, and
      # which land in the registry like any other -- get a placeholder rather
      # than blowing up every caller that walks the registry.
      def rule_name
        if name
          name.split("::").last
        else
          "(anonymous)"
        end
      end

      # Overridden by a rule that should be off unless asked for. Rules that
      # enforce a house preference rather than report a defect default to off,
      # because a linter whose first run is a wall of style noise gets turned
      # off entirely.
      def enabled_by_default?
        true
      end

      def default_severity
        "warning"
      end

      # One line, shown by `remlint --show-rules` and used as the doc comment
      # in the generated default config.
      def description
        ""
      end

      # Only named subclasses. A rule with no name cannot be configured, named
      # in a `remlint:disable` comment, or reported usefully, so it is not one
      # the runner can run -- which is also what keeps the anonymous classes a
      # spec makes from turning up in someone else's lint run.
      def all
        REGISTRY.reject { |rule| rule.name.nil? }
      end

      def find(rule_name)
        all.find { |rule| rule.rule_name == rule_name }
      end
    end

    attr_reader :config, :document, :offenses

    def initialize(config = {})
      @config = config
      @offenses = []
    end

    def run(document)
      @document = document
      @offenses = []
      check
      offenses
    end

    def rule_name
      self.class.rule_name
    end

    # Subclasses implement this.
    def check
      raise NotImplementedError, "#{self.class} must implement #check"
    end

    private

      # `severity:` overrides the configured level for one offence. Only one
      # rule needs it: Syntax, which relays diagnostics Remind has already
      # graded for itself and should not promote a warning to an error.
      def offend(line, message, column: 1, severity: nil)
        @offenses << Offense.new(
          path:     document.path,
          line:     line,
          column:   column,
          severity: severity || configured_severity,
          rule:     rule_name,
          message:  message,
        )
      end

      # Report at a character offset into a logical line, letting the line work
      # out which physical line and column that lands on. This is what a rule
      # working from the token stream wants: it keeps offences inside a
      # continued command pointing at the continuation they are actually on.
      def offend_at(logical_line, offset, message)
        line, column = logical_line.position_at(offset)

        offend(line, message, column: column)
      end

      def configured_severity
        config.fetch("Severity", self.class.default_severity)
      end

      def option(key, default)
        config.fetch(key, default)
      end
  end
end

__END__

require_relative "document"
require_relative "rules/trailing_whitespace"

describe "RemLint::Rule" do
  # Defined inside the spec so the registry assertions have something of their
  # own to find, rather than depending on which real rules happen to be loaded.
  example = Class.new(RemLint::Rule) do
    def self.rule_name = "ExampleRule"

    def check
      document.code_commands.each do |command|
        offend(command.line, "saw #{command.keyword&.name}", column: command.keyword_column)
      end
    end
  end

  document = proc do |text|
    RemLint::Document.new(RemLint::Source.new(path: "t.rem", text: text))
  end

  it "registers every subclass" do
    RemLint::Rule::REGISTRY.should.include example
  end

  it "keeps anonymous subclasses out of the runnable set" do
    # A rule with no name cannot be configured or reported by name, and the
    # ones a spec makes must not leak into anyone else's run.
    RemLint::Rule.all.should.not.include example
  end

  it "collects the offences a check reports" do
    offenses = example.new.run(document.("# note\nMSG hi\n"))

    offenses.length.should == 1
    offenses.first.line.should == 2
    offenses.first.message.should == "saw MSG"
    offenses.first.rule.should == "ExampleRule"
  end

  it "starts empty on each run rather than accumulating" do
    rule = example.new
    rule.run(document.("MSG hi\n"))
    rule.run(document.("MSG hi\n"))

    rule.offenses.length.should == 1
  end

  it "takes severity from configuration, falling back to the rule's default" do
    example.new.run(document.("MSG hi\n")).first.severity.should == "warning"
    example.new("Severity" => "error").run(document.("MSG hi\n")).first.severity.should == "error"
  end

  it "insists a subclass implements check" do
    incomplete = Class.new(RemLint::Rule)

    lambda { incomplete.new.run(document.("MSG hi\n")) }.should.raise NotImplementedError
  end

  it "finds a named rule and nothing else" do
    RemLint::Rule.find("TrailingWhitespace").rule_name.should == "TrailingWhitespace"
    RemLint::Rule.find("ExampleRule").should.be.nil
    RemLint::Rule.find("NoSuchRule").should.be.nil
  end

  it "reports an offset inside a continued command on the right physical line" do
    positional = Class.new(RemLint::Rule) do
      def self.rule_name = "Positional"

      def check
        line = document.logical_lines.first

        offend_at(line, line.text.index("boom"), "found it")
      end
    end

    offense = positional.new.run(document.("SET x 1 + \\\n    boom\n")).first

    offense.line.should == 2
    offense.column.should == 5
  end
end
