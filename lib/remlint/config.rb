# frozen_string_literal: true

require "yaml"
require "pathname"

require_relative "rule"

module RemLint
  # Per-rule settings, merged from the shipped defaults and a `.remlint.yml`.
  #
  # Shaped like RuboCop's: a top-level key per rule, `Enabled` and `Severity`
  # understood for every rule, anything else passed through to the rule that
  # asked for it. `Exclude` at the top level drops paths from the run.
  #
  # Merging is per rule rather than per file: a project that sets
  # `TrailingWhitespace: {Severity: error}` keeps every other rule's defaults
  # instead of silently switching them all off.
  class Config
    DEFAULT_PATH = Pathname.new(__dir__).join("../../config/default.yml").cleanpath

    FILENAME = ".remlint.yml"

    attr_reader :settings

    def initialize(settings = {})
      @settings = settings
    end

    class << self
      def default
        new(load_yaml(DEFAULT_PATH))
      end

      # The defaults with a project file merged over them.
      def load_file(path)
        default.merge(load_yaml(Pathname.new(path)))
      end

      # Walk up from `directory` looking for a `.remlint.yml`, the way every
      # other linter finds its config, so `remlint` works from a subdirectory.
      def discover(directory = Dir.pwd)
        found = ascend(Pathname.new(directory).expand_path)

        if found
          load_file(found)
        else
          default
        end
      end

      def ascend(directory)
        directory.ascend do |candidate|
          path = candidate.join(FILENAME)

          if path.file?
            break path
          end
        end
      end

      def load_yaml(path)
        if path.file?
          YAML.safe_load(path.read, permitted_classes: [], aliases: true) || {}
        else
          {}
        end
      end
    end

    def merge(overrides)
      merged = settings.dup

      overrides.each do |key, value|
        merged[key] = merge_section(settings[key], value)
      end

      Config.new(merged)
    end

    def for_rule(rule_name)
      settings.fetch(rule_name, {})
    end

    # A rule runs unless it is switched off, or unless it is one of the
    # opt-in rules and nothing switched it on.
    def enabled?(rule_class)
      section = for_rule(rule_class.rule_name)

      section.fetch("Enabled", rule_class.enabled_by_default?)
    end

    def excluded?(path)
      exclude_patterns.any? do |pattern|
        File.fnmatch?(pattern, path.to_s, File::FNM_PATHNAME | File::FNM_EXTGLOB)
      end
    end

    def exclude_patterns
      Array(settings["Exclude"])
    end

    # Rules the config leaves running, instantiated with their own section.
    def rules
      Rule.all.select { |rule_class| enabled?(rule_class) }.map do |rule_class|
        rule_class.new(for_rule(rule_class.rule_name))
      end
    end

    # `--only` on the command line: run these and nothing else, regardless of
    # what the file says, but keep each rule's configured options.
    def only(rule_names)
      wanted = Array(rule_names)
      merged = settings.dup

      Rule.all.each do |rule_class|
        section = merged.fetch(rule_class.rule_name, {}).dup
        section["Enabled"] = wanted.include?(rule_class.rule_name)
        merged[rule_class.rule_name] = section
      end

      Config.new(merged)
    end

    private

      # A rule's section merges key by key; anything else -- Exclude, scalars --
      # is replaced outright, because a project listing its own excludes means
      # those and not those plus ours.
      def merge_section(existing, override)
        if existing.is_a?(Hash) && override.is_a?(Hash)
          existing.merge(override)
        else
          override
        end
      end
  end
end

__END__

require_relative "document"
require_relative "rules/line_length"
require_relative "rules/trailing_whitespace"

describe "RemLint::Config" do
  # A pair of registered rules to configure, so the assertions do not depend on
  # which real rules happen to be loaded.
  on_by_default = Class.new(RemLint::Rule) do
    def self.rule_name = "SpecOnByDefault"

    def check = nil
  end

  off_by_default = Class.new(RemLint::Rule) do
    def self.rule_name = "SpecOffByDefault"
    def self.enabled_by_default? = false

    def check = nil
  end

  describe "defaults" do
    it "ships a config for every rule that is on by default" do
      RemLint::Config.default.enabled?(on_by_default).should.be.true
    end

    it "leaves an opt-in rule off until something asks for it" do
      RemLint::Config.default.enabled?(off_by_default).should.be.false
    end
  end

  describe "merging" do
    config = RemLint::Config.new(
      "SpecOnByDefault" => { "Enabled" => true, "Severity" => "warning" },
    )

    it "keeps the keys an override does not mention" do
      merged = config.merge("SpecOnByDefault" => { "Severity" => "error" })

      merged.for_rule("SpecOnByDefault").should == { "Enabled" => true, "Severity" => "error" }
    end

    it "leaves other rules alone" do
      merged = config.merge("SpecOffByDefault" => { "Enabled" => true })

      merged.enabled?(on_by_default).should.be.true
      merged.enabled?(off_by_default).should.be.true
    end

    it "replaces a list outright rather than appending to it" do
      merged = config.merge("Exclude" => ["vendor/**/*"])

      merged.exclude_patterns.should == ["vendor/**/*"]
    end

    it "does not mutate the config it was merged from" do
      config.merge("SpecOnByDefault" => { "Severity" => "error" })

      config.for_rule("SpecOnByDefault").fetch("Severity").should == "warning"
    end
  end

  describe "enabling and disabling" do
    it "honours an explicit Enabled: false" do
      config = RemLint::Config.new("SpecOnByDefault" => { "Enabled" => false })

      config.enabled?(on_by_default).should.be.false
    end

    it "honours an explicit Enabled: true on an opt-in rule" do
      config = RemLint::Config.new("SpecOffByDefault" => { "Enabled" => true })

      config.enabled?(off_by_default).should.be.true
    end

    it "instantiates each enabled rule with its own section" do
      config = RemLint::Config.new("TrailingWhitespace" => { "Severity" => "warning" })
      rule = config.rules.find { |candidate| candidate.rule_name == "TrailingWhitespace" }

      rule.config.should == { "Severity" => "warning" }
    end
  end

  describe "only" do
    it "runs the named rules and nothing else" do
      config = RemLint::Config.default.only(["LineLength"])

      # LineLength is off by default and TrailingWhitespace is on; --only
      # inverts both, which is the whole point of it.
      config.enabled?(RemLint::Rules::LineLength).should.be.true
      config.enabled?(RemLint::Rules::TrailingWhitespace).should.be.false
    end

    it "keeps the options of the rules it leaves running" do
      config = RemLint::Config
        .new("SpecOffByDefault" => { "Severity" => "error" })
        .only(["SpecOffByDefault"])

      config.for_rule("SpecOffByDefault").fetch("Severity").should == "error"
    end
  end

  describe "excludes" do
    config = RemLint::Config.new("Exclude" => ["examples/*.rem", "vendor/**/*"])

    it "matches a shell pattern against the path" do
      config.excluded?("examples/tflag.rem").should.be.true
      config.excluded?("vendor/a/b/c.rem").should.be.true
      config.excluded?("holidays.rem").should.be.false
    end

    it "does not let a single-star pattern cross a directory boundary" do
      config.excluded?("examples/nested/a.rem").should.be.false
    end
  end
end
