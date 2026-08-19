# frozen_string_literal: true

require "pathname"

require_relative "config"
require_relative "document"
require_relative "extractors"

module RemLint
  # Walks paths, extracts Remind out of them, runs the enabled rules, and drops
  # whatever the file itself asked to be quiet about.
  class Runner
    # `# remlint:disable UnbalancedBlocks, TrailingWhitespace`, or `all`.
    # Recognised after either comment character, and mid-line, so it can sit at
    # the end of the line it applies to.
    DISABLE = /[#;]\s*remlint:disable\s+(?<rules>[\w\s,-]+)/

    ALL = "all"

    # Extensions worth opening when walking a directory. A file with no
    # extension is opened too, because `examples/astro` and `examples/ansitext`
    # have none and are where most of the Remind in that directory lives.
    CANDIDATE = /\.(rem|sh|bash)\z|\A[^.]+\z/

    attr_reader :config

    def initialize(config = Config.default)
      @config = config
    end

    # Returns the offences, worst-placed first in reading order.
    def run(paths)
      files(paths).flat_map { |path| lint_file(path) }.sort_by(&:sort_key)
    end

    # The files a set of paths expands to: a named file is taken as given, a
    # named directory is walked.
    def files(paths)
      Array(paths).flat_map { |path| expand(path) }.uniq.reject { |path| config.excluded?(path) }
    end

    def lint_file(path)
      text = read(path)

      if text.nil?
        []
      else
        lint_text(path, text)
      end
    end

    def lint_text(path, text)
      rules = config.rules

      Extractors.extract(path, text).flat_map do |source|
        lint_source(Document.new(source), rules)
      end
    end

    private

      def expand(path)
        pathname = Pathname.new(path)

        if pathname.directory?
          walk(pathname)
        else
          [path.to_s]
        end
      end

      def walk(directory)
        directory.find.filter_map do |entry|
          if entry.file? && entry.basename.to_s.match?(CANDIDATE)
            entry.to_s
          end
        end
      end

      # A file Remind can read is a file of bytes; one that is not valid UTF-8
      # is not Remind's problem or ours, and neither is one we cannot open.
      def read(path)
        text = File.read(path, encoding: "UTF-8")

        if text.valid_encoding?
          text
        end
      rescue SystemCallError
        nil
      end

      def lint_source(document, rules)
        found = rules.flat_map { |rule| rule.run(document) }

        found.reject { |offense| disabled?(document, offense) }
      end

      # A directive applies to the line it is on and to the line below it, so
      # it can be written after the offending line or above it -- puppet-lint's
      # two forms, which cover the case where the line has no room left.
      def disabled?(document, offense)
        index = offense.line - document.line_offset - 1

        [index, index - 1].any? do |candidate|
          directive_covers?(document.raw_lines[candidate], offense.rule, candidate)
        end
      end

      def directive_covers?(raw, rule_name, index)
        match = index >= 0 && raw&.match(DISABLE)

        if match
          named = match[:rules].split(/[,\s]+/).reject(&:empty?)

          named.include?(ALL) || named.include?(rule_name)
        end
      end
  end
end

__END__

require "tempfile"

require_relative "rules/trailing_whitespace"
require_relative "rules/unbalanced_blocks"

describe "RemLint::Runner" do
  # Just the two rules, so the assertions do not shift when a rule is added.
  config = RemLint::Config.default.only(%w[TrailingWhitespace UnbalancedBlocks])
  runner = RemLint::Runner.new(config)

  lint = proc { |text, path = "t.rem"| runner.lint_text(path, text) }
  rules_of = proc { |text| lint.(text).map(&:rule) }

  describe "linting text" do
    it "runs every enabled rule" do
      rules_of.("IF a\nMSG hi \n").sort.should == %w[TrailingWhitespace UnbalancedBlocks]
    end

    it "returns nothing for a clean file" do
      lint.("IF a\n   MSG hi\nENDIF\n").should.be.empty
    end

    it "runs only the rules the config leaves on" do
      only_blocks = RemLint::Runner.new(RemLint::Config.default.only(%w[UnbalancedBlocks]))

      only_blocks.lint_text("t.rem", "IF a\nMSG hi \n").map(&:rule).should == ["UnbalancedBlocks"]
    end

    it "sorts offences into reading order when running over real paths" do
      Tempfile.create(["spec", ".rem"]) do |file|
        file.write("MSG trailing \nIF a\nMSG also trailing \n")
        file.flush

        runner.run([file.path]).map { |offense| [offense.line, offense.rule] }.should ==
          [[1, "TrailingWhitespace"], [2, "UnbalancedBlocks"], [3, "TrailingWhitespace"]]
      end
    end
  end

  describe "extraction" do
    it "lints a .rem file whole" do
      lint.("MSG hi \n").length.should == 1
    end

    it "lints a heredoc and reports positions in the enclosing file" do
      script = "#!/bin/sh\n# note\nremind - <<'EOF'\nMSG hi \nEOF\n"

      offenses = lint.(script, "ansitext")
      offenses.length.should == 1
      offenses.first.line.should == 4
    end

    it "ignores a file that holds no Remind at all" do
      lint.("#!/bin/sh\necho hello \n", "build.sh").should.be.empty
    end
  end

  describe "disable comments" do
    it "drops an offence named on the same line" do
      lint.("MSG hi  # remlint:disable TrailingWhitespace\n").should.be.empty
    end

    it "drops an offence named on the line above" do
      lint.("# remlint:disable TrailingWhitespace\nMSG hi \n").should.be.empty
    end

    it "accepts the semicolon comment character too" do
      lint.("; remlint:disable TrailingWhitespace\nMSG hi \n").should.be.empty
    end

    it "drops several rules named together" do
      text = "# remlint:disable TrailingWhitespace, UnbalancedBlocks\nIF a\nMSG hi \n"

      lint.(text).map(&:rule).should == ["TrailingWhitespace"]
    end

    it "drops everything when told all" do
      lint.("# remlint:disable all\nMSG hi \n").should.be.empty
    end

    it "leaves an offence a directive does not name" do
      lint.("# remlint:disable UnbalancedBlocks\nMSG hi \n").map(&:rule).should ==
        ["TrailingWhitespace"]
    end

    it "does not reach a line further than one below the directive" do
      lint.("# remlint:disable TrailingWhitespace\nMSG ok\nMSG hi \n").length.should == 1
    end
  end

  describe "walking paths" do
    it "keeps a named file as given" do
      runner.files(["examples/holidays.rem"]).should == ["examples/holidays.rem"]
    end

    it "drops a path the config excludes" do
      excluding = RemLint::Runner.new(RemLint::Config.new("Exclude" => ["vendor/**/*"]))

      excluding.files(["vendor/a.rem", "b.rem"]).should == ["b.rem"]
    end

    it "returns nothing for a file it cannot read" do
      runner.lint_file("/nonexistent/nowhere.rem").should.be.empty
    end
  end
end
