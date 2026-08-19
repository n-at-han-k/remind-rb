# frozen_string_literal: true

require_relative "offense"

module RemLint
  # Renders offences for a terminal, an editor, or a CI annotation.
  #
  # The default line is `path:line:column: severity: [Rule] message`, which
  # vim's default `errorformat` already parses and which most CI annotators
  # recognise. `--log-format` overrides it with the same `%{...}` placeholders
  # puppet-lint uses, so a project that needs GitHub's `::error file=...`
  # shape can have it without a new formatter class.
  class Formatter
    DEFAULT_TEMPLATE = "%{path}:%{line}:%{column}: %{severity}: [%{rule}] %{message}"

    attr_reader :template

    def initialize(template: DEFAULT_TEMPLATE)
      @template = template
    end

    def lines(offenses)
      offenses.map { |offense| offense.format_with(template) }
    end

    # One line per offence, then a count. Empty output for a clean run: a
    # linter that prints "0 offences" on every commit trains people to stop
    # reading its output.
    def render(offenses)
      if offenses.empty?
        ""
      else
        "#{(lines(offenses) + [summary(offenses)]).join("\n")}\n"
      end
    end

    def summary(offenses)
      counts = SEVERITIES.filter_map do |severity|
        count = offenses.count { |offense| offense.severity == severity }

        if count.positive?
          "#{count} #{severity}#{count == 1 ? '' : 's'}"
        end
      end

      "#{offenses.length} offence#{offenses.length == 1 ? '' : 's'} (#{counts.join(', ')})"
    end
  end
end

__END__

describe "RemLint::Formatter" do
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

  it "renders the default line format" do
    RemLint::Formatter.new.lines([offense.()]).should ==
      ["holidays.rem:12:4: warning: [TrailingWhitespace] Trailing whitespace"]
  end

  it "renders through a caller-supplied template" do
    formatter = RemLint::Formatter.new(template: "::error file=%{path},line=%{line}::%{message}")

    formatter.lines([offense.()]).should == ["::error file=holidays.rem,line=12::Trailing whitespace"]
  end

  it "prints nothing at all for a clean run" do
    RemLint::Formatter.new.render([]).should == ""
  end

  it "ends the report with a count by severity" do
    report = RemLint::Formatter.new.render([offense.(), offense.(severity: "error")])

    report.should.match(/2 offences \(1 error, 1 warning\)\n\z/)
  end

  it "uses the singular for one of anything" do
    RemLint::Formatter.new.summary([offense.()]).should == "1 offence (1 warning)"
  end

  it "lists only the severities that occurred, worst first" do
    offenses = [offense.(severity: "info"), offense.(severity: "error")]

    RemLint::Formatter.new.summary(offenses).should == "2 offences (1 error, 1 info)"
  end
end
