# frozen_string_literal: true

require_relative "../rule"

module RemLint
  module Rules
    # Files missing a licence identifier near the top.
    #
    # Off by default, because it is a project policy rather than a Remind fact.
    # It exists because it is a policy Remind itself keeps: every file under
    # `examples/` carries `SPDX-License-Identifier: GPL-2.0-only` in its header
    # comment, and a linter is the only thing that keeps that true as files are
    # added.
    #
    # `Pattern` is a regular expression as a string, so a project with a
    # different licence or a different marker configures it rather than
    # forking the rule. Only the first `WithinLines` lines are searched, so a
    # mention halfway down a long file does not count as a header.
    class LicenseHeader < Rule
      DEFAULT_PATTERN = "SPDX-License-Identifier:\\s*\\S+"
      DEFAULT_WITHIN = 10

      def self.enabled_by_default?
        false
      end

      def self.description
        "A licence identifier in the first few lines of the file."
      end

      def check
        within = option("WithinLines", DEFAULT_WITHIN)
        pattern = Regexp.new(option("Pattern", DEFAULT_PATTERN))

        if !document.raw_lines.empty? && !header_matches?(pattern, within)
          offend(document.line_number_at(0), "Missing a licence identifier in the first #{within} lines")
        end
      end

      private

        def header_matches?(pattern, within)
          document.raw_lines.first(within).any? { |raw| raw.match?(pattern) }
        end
    end
  end
end

__END__

require_relative "../document"

describe "RemLint::Rules::LicenseHeader" do
  lint = proc do |text, config = {}|
    source = RemLint::Source.new(path: "t.rem", text: text)

    RemLint::Rules::LicenseHeader.new(config).run(RemLint::Document.new(source))
  end

  it "is off unless the configuration asks for it" do
    RemLint::Rules::LicenseHeader.enabled_by_default?.should.be.false
  end

  it "accepts the header Remind's own examples carry" do
    lint.("# Demo\n# SPDX-License-Identifier: GPL-2.0-only\nMSG hi\n").should.be.empty
  end

  it "reports a file with no identifier" do
    offenses = lint.("# Demo\nMSG hi\n")

    offenses.length.should == 1
    offenses.first.line.should == 1
    offenses.first.message.should.match(/licence identifier/)
  end

  it "does not count an identifier below the header" do
    body = "MSG hi\n" * 12

    lint.("#{body}# SPDX-License-Identifier: GPL-2.0-only\n").length.should == 1
  end

  it "honours a wider WithinLines" do
    body = "MSG hi\n" * 12

    lint.("#{body}# SPDX-License-Identifier: GPL-2.0-only\n", "WithinLines" => 20).should.be.empty
  end

  it "honours a project's own pattern" do
    lint.("# Copyright 2026 Someone\n", "Pattern" => "Copyright \\d{4}").should.be.empty
  end

  it "says nothing about an empty file" do
    lint.("").should.be.empty
  end

  it "reports a heredoc at its position in the enclosing file" do
    source = RemLint::Source.new(path: "astro", text: "MSG hi\n", line_offset: 12)

    RemLint::Rules::LicenseHeader.new.run(RemLint::Document.new(source)).first.line.should == 13
  end
end
