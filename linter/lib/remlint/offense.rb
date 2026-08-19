# frozen_string_literal: true

module RemLint
  # Ordered worst-first, so a run that reports only the top N reports the N
  # that matter.
  #
  # Defined out here rather than inside the Struct body below: a constant
  # assigned inside a block belongs to the lexical scope around the block, not
  # to the class the block configures, so `Offense::SEVERITIES` would not have
  # existed.
  SEVERITIES = %w[error warning info].freeze

  # One thing a rule found, at one place in one file.
  #
  # The default rendering is `path:line:column: severity: [Rule] message`,
  # which vim's default `errorformat` reads, which GitHub Actions' problem
  # matchers read, and which `sort` orders correctly. The format is also
  # configurable, following puppet-lint, because the one thing every CI system
  # agrees on is that it wants a slightly different format.
  Offense = Struct.new(
    :path,
    :line,
    :column,
    :severity,
    :rule,
    :message,
    keyword_init: true,
  ) do
    def initialize(path:, line:, rule:, message:, column: 1, severity: "warning")
      super
    end

    def severity_rank
      SEVERITIES.index(severity) || SEVERITIES.length
    end

    def error?
      severity == "error"
    end

    # At or above the given severity, where "above" means closer to error.
    def at_least?(level)
      severity_rank <= (SEVERITIES.index(level) || SEVERITIES.length)
    end

    def to_s
      format_with("%{path}:%{line}:%{column}: %{severity}: [%{rule}] %{message}")
    end

    # `%{path}`, `%{line}`, `%{column}`, `%{severity}`, `%{rule}`, `%{message}`.
    def format_with(template)
      format(
        template,
        path:     path,
        line:     line,
        column:   column,
        severity: severity,
        rule:     rule,
        message:  message,
      )
    end

    # File, then position, then severity: the order someone reads them in.
    def sort_key
      [path, line, column, severity_rank, rule]
    end
  end
end

__END__

describe "RemLint::Offense" do
  offense = proc do |overrides = {}|
    defaults = {
      path:    "holidays.rem",
      line:    12,
      column:  4,
      rule:    "TrailingWhitespace",
      message: "Trailing whitespace",
    }

    RemLint::Offense.new(**defaults.merge(overrides))
  end

  it "renders in a format vim's errorformat reads" do
    offense.().to_s.should == "holidays.rem:12:4: warning: [TrailingWhitespace] Trailing whitespace"
  end

  it "defaults to column 1 and warning severity" do
    bare = RemLint::Offense.new(path: "a.rem", line: 1, rule: "R", message: "m")

    bare.column.should == 1
    bare.severity.should == "warning"
  end

  it "renders through a caller-supplied template" do
    offense.().format_with("%{line}: %{message}").should == "12: Trailing whitespace"
  end

  it "knows whether it meets a severity threshold" do
    offense.(severity: "error").should.be.error
    offense.(severity: "error").at_least?("warning").should.be.true
    offense.(severity: "warning").at_least?("error").should.be.false
    offense.(severity: "info").at_least?("warning").should.be.false
  end

  it "sorts by file, then position, then severity" do
    unsorted = [
      offense.(line: 12, column: 9),
      offense.(line: 3),
      offense.(path: "a.rem", line: 99),
    ]

    unsorted.sort_by(&:sort_key).map { |o| [o.path, o.line, o.column] }.should ==
      [["a.rem", 99, 4], ["holidays.rem", 3, 4], ["holidays.rem", 12, 9]]
  end
end
