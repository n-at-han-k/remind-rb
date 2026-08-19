# frozen_string_literal: true

require_relative "../rule"

module RemLint
  module Rules
    # Moon and season selectors outside their four-element sets.
    #
    # `moondate`, `moondatetime` and `moontime` take a phase: 0 new, 1 first
    # quarter, 2 full, 3 last quarter. `soleq` takes an event: 0 March equinox,
    # 1 June solstice, 2 September equinox, 3 December solstice. Both are
    # closed sets of four, so a literal 4 is always wrong and always visible
    # without running anything.
    #
    # Remind agrees -- `moondate(4)` is `Number too high` -- but says so on the
    # day the line is reached, which for a moon reminder is the day it was
    # supposed to fire.
    class MoonPhaseArgument < Rule
      PHASES = {
        "moondate"     => "a moon phase",
        "moondatetime" => "a moon phase",
        "moontime"     => "a moon phase",
        "soleq"        => "a solstice or equinox",
      }.freeze

      MEANINGS = {
        "a moon phase"          => "0 new, 1 first quarter, 2 full, 3 last quarter",
        "a solstice or equinox" => "0 March equinox, 1 June solstice, " \
                                    "2 September equinox, 3 December solstice",
      }.freeze

      LIMIT = 3

      def self.default_severity
        "error"
      end

      def self.description
        "A moon phase or solstice selector outside the four values it accepts."
      end

      def check
        document.logical_lines.each_with_index do |logical_line, index|
          if document.commands[index].code?
            check_line(logical_line)
          end
        end
      end

      private

        def check_line(logical_line)
          tokens = document.tokens_for(logical_line)

          tokens.each_index do |index|
            selector = literal_selector(tokens, index)

            if selector
              report(logical_line, tokens[index], selector)
            end
          end
        end

        # `name ( <number>` -- the selector is always the first argument.
        def literal_selector(tokens, index)
          token = tokens[index]
          argument = tokens[index + 2]

          if token.type == :function && PHASES.key?(token.value.downcase) &&
             tokens[index + 1]&.type == :lparen && argument&.type == :number
            argument
          end
        end

        def report(logical_line, name, argument)
          value = argument.value.to_i

          if value > LIMIT
            kind = PHASES.fetch(name.value.downcase)

            offend_at(logical_line, argument.offset, message(name.value, kind, value))
          end
        end

        def message(name, kind, value)
          "`#{name}(#{value})` is outside the four values #{kind} takes " \
          "(#{MEANINGS.fetch(kind)}); Remind answers `Number too high`"
        end
    end
  end
end

__END__

require_relative "../document"

describe "RemLint::Rules::MoonPhaseArgument" do
  lint = proc do |text|
    source = RemLint::Source.new(path: "t.rem", text: text)

    RemLint::Rules::MoonPhaseArgument.new.run(RemLint::Document.new(source))
  end

  messages = proc { |text| lint.(text).map(&:message) }

  describe "selectors that exist" do
    it "accepts the four moon phases" do
      # include/moonphases.rem writes exactly these.
      (0..3).each do |phase|
        lint.("REM [moondatetime(#{phase})] MSG Moon\n").should.be.empty
      end
    end

    it "accepts the four solstice and equinox events" do
      (0..3).each do |event|
        lint.("REM [datepart(soleq(#{event}, $U))] MSG Season\n").should.be.empty
      end
    end

    it "accepts moondate and moontime too" do
      lint.("MSG [moondate(2)] [moontime(2)]\n").should.be.empty
    end
  end

  describe "selectors that do not" do
    it "reports a moon phase of 4" do
      messages.("REM [moondatetime(4)] MSG Moon\n").first.should ==
        "`moondatetime(4)` is outside the four values a moon phase takes " \
        "(0 new, 1 first quarter, 2 full, 3 last quarter); Remind answers `Number too high`"
    end

    it "reports a solstice selector of 4" do
      messages.("MSG [soleq(4, $U)]\n").first.should.match(/a solstice or equinox takes/)
    end

    it "reports each bad selector on a line" do
      messages.("MSG [moondate(4)] [moondate(9)]\n").length.should == 2
    end

    it "points at the argument" do
      text = "MSG [moondate(4)]\n"

      lint.(text).first.column.should == text.index("4") + 1
    end
  end

  it "says nothing about a computed selector" do
    lint.("MSG [moondate(n)]\n").should.be.empty
  end

  it "says nothing about another function taking a large number" do
    lint.("MSG [max(4, 9)]\n").should.be.empty
  end

  it "says nothing about comments" do
    lint.("# MSG [moondate(4)]\n").should.be.empty
  end

  it "reports at error severity" do
    lint.("MSG [moondate(4)]\n").first.severity.should == "error"
  end
end
