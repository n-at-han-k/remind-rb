# frozen_string_literal: true

require_relative "../rule"

module RemLint
  module Rules
    # Colour components outside 0-255.
    #
    # Remind rejects them -- `if (r > 255 || g > 255 || b > 255) return E_2HIGH`
    # in src/funcs.c for `ansicolor`, and the same bound in src/var.c for
    # `$DefaultColor` -- but only when the line runs, and `rem2ps` silently
    # clamps instead (src/rem2ps.c). A component typed as `2555` therefore
    # renders as something plausible in one output mode and fails in another,
    # which is the worst way for a mistake to behave.
    #
    # Three places carry components, and all three are hand-typed integers in
    # practice, which is exactly when a linter can help:
    #
    #   SPECIAL COLOR r g b <text>     examples/astro has sixteen of these
    #   SPECIAL SHADE r g b            tests/shade.rem has one per weekday
    #   [ansicolor(r, g, b)]           examples/ansitext, examples/alignment
    #
    # `ansicolor` also takes a one-argument form (`ansicolor("")`, the reset)
    # and an optional fourth background flag; only the three components are
    # range-checked, and only when they are literal integers.
    class ColorComponentRange < Rule
      MINIMUM = 0
      MAXIMUM = 255

      # `COLOR`, and the spelling Remind also accepts.
      SPECIAL_KINDS = %w[COLOR COLOUR SHADE].freeze

      # `SPECIAL COLOR 255 128 0 rest...` -- three integers after the keyword.
      SPECIAL = /\A(?<kind>[A-Za-z]+)\s+(?<r>-?\d+)\s+(?<g>-?\d+)\s+(?<b>-?\d+)\b/

      CHANNELS = %w[red green blue].freeze

      def self.default_severity
        "error"
      end

      def self.description
        "Colour components outside the 0-255 Remind accepts."
      end

      def check
        document.code_commands.each do |command|
          check_special(command)
          check_ansicolor(command)
        end
      end

      private

        def check_special(command)
          match = special_components(command)

          if match
            report_components(command, match[:kind].upcase, [match[:r], match[:g], match[:b]])
          end
        end

        # The components sit after `SPECIAL`, which may itself be preceded by a
        # whole trigger (`REM [moondatetime(0)] +60 SPECIAL COLOR ...`), so the
        # keyword is found in the text rather than assumed to open the line.
        def special_components(command)
          rest = command.text[/\bSPECIAL\s+(.*)\z/mi, 1]
          match = rest&.match(SPECIAL)

          if match && SPECIAL_KINDS.include?(match[:kind].upcase)
            match
          end
        end

        def check_ansicolor(command)
          logical_line = command.logical_line
          tokens = document.tokens_for(logical_line)

          tokens.each_with_index do |token, index|
            if token.type == :function && token.value.casecmp?("ansicolor")
              report_components(command, "ansicolor", literal_arguments(tokens, index))
            end
          end
        end

        # The first three arguments, and only when each is an integer literal.
        # `ansicolor("")` and `ansicolor(r, g, b)` with computed components
        # both yield nothing to check.
        #
        # The arguments are split on top-level commas rather than picked out by
        # position, because the lexer emits a minus sign as its own token:
        # `ansicolor(-1, 0, 0)` reads as `-`, `1`, `,`, ... and taking the
        # numbers alone would see a perfectly in-range 1.
        def literal_arguments(tokens, index)
          split_arguments(tokens, index + 1).first(3).filter_map { |group| integer(group) }
        end

        def split_arguments(tokens, open_index)
          groups = [[]]
          depth = 0
          cursor = open_index

          if tokens[cursor]&.type != :lparen
            groups = []
          else
            depth, cursor = 1, cursor + 1

            while cursor < tokens.length && depth.positive?
              depth = collect(tokens[cursor], groups, depth)
              cursor += 1
            end
          end

          groups
        end

        # Returns the depth after this token, having filed the token under the
        # argument it belongs to. The call's own closing paren is the one thing
        # not filed anywhere -- it ends the walk instead.
        def collect(token, groups, depth)
          case token.type
          when :lparen, :lbracket then descend(groups, token, depth)
          when :rparen, :rbracket then ascend(groups, token, depth)
          when :comma             then comma(groups, token, depth)
          else
            groups.last << token
            depth
          end
        end

        def descend(groups, token, depth)
          groups.last << token

          depth + 1
        end

        def ascend(groups, token, depth)
          if depth > 1
            groups.last << token
          end

          depth - 1
        end

        def comma(groups, token, depth)
          if depth == 1
            groups << []
          else
            groups.last << token
          end

          depth
        end

        # A group is a literal only if it is a bare number, optionally signed.
        def integer(group)
          text = group.map(&:value).join

          if text.match?(/\A[+-]?\d+\z/)
            text
          end
        end

        def report_components(command, kind, components)
          components.each_with_index do |component, index|
            value = Integer(component, exception: false)

            if !value.nil? && !(MINIMUM..MAXIMUM).cover?(value)
              offend(
                command.line,
                "#{kind} #{CHANNELS.fetch(index)} component #{value} is outside " \
                "#{MINIMUM}-#{MAXIMUM}",
                column: command.keyword_column,
              )
            end
          end
        end
    end
  end
end

__END__

require_relative "../document"

describe "RemLint::Rules::ColorComponentRange" do
  lint = proc do |text|
    source = RemLint::Source.new(path: "t.rem", text: text)

    RemLint::Rules::ColorComponentRange.new.run(RemLint::Document.new(source))
  end

  messages = proc { |text| lint.(text).map(&:message) }

  describe "SPECIAL COLOR" do
    it "accepts components in range" do
      lint.("REM Mon SPECIAL COLOR 255 128 0 Sunset\n").should.be.empty
    end

    it "accepts the boundary values" do
      lint.("SPECIAL COLOR 0 0 0 x\nSPECIAL COLOR 255 255 255 y\n").should.be.empty
    end

    it "reports a component above 255" do
      messages.("SPECIAL COLOR 2555 128 0 x\n").should ==
        ["COLOR red component 2555 is outside 0-255"]
    end

    it "reports a negative component" do
      messages.("SPECIAL COLOR 255 -1 0 x\n").should ==
        ["COLOR green component -1 is outside 0-255"]
    end

    it "names the blue channel" do
      messages.("SPECIAL COLOR 0 0 999 x\n").should ==
        ["COLOR blue component 999 is outside 0-255"]
    end

    it "reports every bad component on the line" do
      messages.("SPECIAL COLOR 300 400 500 x\n").length.should == 3
    end

    it "accepts the COLOUR spelling" do
      messages.("SPECIAL COLOUR 300 0 0 x\n").should ==
        ["COLOUR red component 300 is outside 0-255"]
    end

    it "finds the components after a full trigger, as astro writes them" do
      messages.("REM [moondatetime(0)] +60 SPECIAL COLOR 300 0 0 New moon\n").length.should == 1
    end
  end

  describe "SPECIAL SHADE" do
    it "accepts components in range" do
      lint.("REM Mon SPECIAL SHADE 255 255 204\n").should.be.empty
    end

    it "reports one out of range" do
      messages.("REM Mon SPECIAL SHADE 256 255 204\n").should ==
        ["SHADE red component 256 is outside 0-255"]
    end
  end

  describe "ansicolor" do
    it "accepts components in range" do
      lint.("MSG [ansicolor(0, 255, 0)]red[ansicolor(\"\")]\n").should.be.empty
    end

    it "reports one out of range" do
      messages.("MSG [ansicolor(0, 300, 0)]x\n").should ==
        ["ansicolor green component 300 is outside 0-255"]
    end

    it "accepts the four-argument background form" do
      lint.("MSG [ansicolor(255, 255, 255)][ansicolor(0, 0, 0, 1)]x\n").should.be.empty
    end

    it "says nothing about the reset form" do
      lint.(%(MSG [ansicolor("")]\n)).should.be.empty
    end

    it "reports a negative component" do
      # The lexer emits the minus as its own token, so this only works because
      # the arguments are reassembled rather than picked out by position.
      messages.("MSG [ansicolor(-1, 0, 0)]\n").should ==
        ["ansicolor red component -1 is outside 0-255"]
    end

    it "says nothing when the components are computed" do
      lint.("MSG [ansicolor(r, g, b)]\n").should.be.empty
    end

    it "matches the function name case-insensitively" do
      messages.("MSG [ANSICOLOR(300, 0, 0)]\n").length.should == 1
    end
  end

  describe "what it stays quiet about" do
    it "says nothing about a SPECIAL it does not know" do
      lint.("SPECIAL HTMLCLASS 999 999 999\n").should.be.empty
    end

    it "says nothing about ordinary numbers on a line" do
      lint.("MSG 300 400 500 items\n").should.be.empty
    end

    it "says nothing about comments" do
      lint.("# SPECIAL COLOR 999 0 0 example\n").should.be.empty
    end
  end

  it "reports at error severity" do
    lint.("SPECIAL COLOR 300 0 0 x\n").first.severity.should == "error"
  end
end
