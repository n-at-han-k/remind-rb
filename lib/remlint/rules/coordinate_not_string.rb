# frozen_string_literal: true

require_relative "../rule"
require_relative "../expr_lexer"

module RemLint
  module Rules
    # `$Latitude` or `$Longitude` set to something that is not a string.
    #
    # Remind has no floating-point type. A coordinate therefore has to arrive
    # as a STRING and be parsed from it -- `SET $Latitude "45.42"`, with the
    # quotes. `SET $Latitude 45.42` is not a near miss with a rounding error in
    # it; `45.42` is not a Remind literal at all.
    #
    # `examples/astro` gets this right the hard way, threading the values in
    # from the shell as strings:
    #
    #   remind -g "-i\$Latitude=\"$latitude\"" ...
    #
    # The failure is quiet and confident. Remind falls back or truncates, and
    # then reports sunrise and sunset times that look entirely plausible and
    # are for somewhere else.
    class CoordinateNotString < Rule
      COORDINATES = %w[latitude longitude].freeze

      # `SET $Latitude <value>`, with the value running to end of line.
      ASSIGNMENT = /\A\$(?<name>\w+)\s+(?<value>.+)\z/m

      def self.default_severity
        "error"
      end

      def self.description
        "$Latitude or $Longitude set to something other than a string."
      end

      def check
        document.code_commands.each do |command|
          if command.keyword?("SET")
            check_assignment(command)
          end
        end
      end

      private

        def check_assignment(command)
          match = command.args.match(ASSIGNMENT)

          if match && COORDINATES.include?(match[:name].downcase)
            check_value(command, match)
          end
        end

        def check_value(command, match)
          value = match[:value].strip
          tokens = ExprLexer.significant(value)

          if literal_non_string?(tokens)
            offend(
              command.line,
              "`$#{match[:name]}` takes a STRING -- Remind has no floating-point " \
              "type, so write `\"#{value}\"`",
              column: command.keyword_column,
            )
          end
        end

        # Only a literal is reported. A single string token is right; a single
        # bracketed or computed value cannot be judged without running it, and
        # `[latitude_from_gps()]` is a perfectly good way to set this.
        def literal_non_string?(tokens)
          types = tokens.map(&:type)

          types.first != :string &&
            !types.include?(:lbracket) &&
            !types.include?(:function) &&
            !types.include?(:name)
        end
    end
  end
end

__END__

require_relative "../document"

describe "RemLint::Rules::CoordinateNotString" do
  lint = proc do |text|
    source = RemLint::Source.new(path: "t.rem", text: text)

    RemLint::Rules::CoordinateNotString.new.run(RemLint::Document.new(source))
  end

  messages = proc { |text| lint.(text).map(&:message) }

  describe "coordinates written as numbers" do
    it "reports a bare decimal" do
      messages.("SET $Latitude 45.42\n").first.should ==
        %(`$Latitude` takes a STRING -- Remind has no floating-point type, so write `"45.42"`)
    end

    it "reports a negative decimal" do
      messages.("SET $Longitude -75.69\n").length.should == 1
    end

    it "reports a bare integer" do
      messages.("SET $Latitude 45\n").length.should == 1
    end

    it "reports both coordinates" do
      messages.("SET $Latitude 45.42\nSET $Longitude -75.69\n").length.should == 2
    end

    it "matches the variable name case-insensitively" do
      messages.("SET $latitude 45.42\n").length.should == 1
      messages.("SET $LONGITUDE 45.42\n").length.should == 1
    end

    it "points at the keyword" do
      lint.("   SET $Latitude 45.42\n").first.column.should == 4
    end
  end

  describe "coordinates written correctly" do
    it "accepts a double-quoted string" do
      lint.(%(SET $Latitude "45.42"\n)).should.be.empty
    end

    it "accepts a negative value in a string" do
      lint.(%(SET $Longitude "-75.69"\n)).should.be.empty
    end

    it "accepts the degrees-minutes-seconds string form" do
      lint.(%(SET $Latitude "45 25 12"\n)).should.be.empty
    end
  end

  describe "values it cannot judge" do
    it "says nothing about a pasted expression" do
      lint.("SET $Latitude [gps_latitude()]\n").should.be.empty
    end

    it "says nothing about a function call" do
      lint.("SET $Latitude coerce(\"STRING\", x)\n").should.be.empty
    end

    it "says nothing about a variable" do
      # examples/astro feeds these in with remind -i$Latitude="..."
      lint.("SET $Latitude mylat\n").should.be.empty
    end
  end

  describe "what it leaves alone" do
    it "says nothing about other system variables" do
      lint.("SET $FormWidth 80\n").should.be.empty
    end

    it "says nothing about an ordinary variable of the same name" do
      lint.("SET Latitude 45.42\n").should.be.empty
    end

    it "says nothing about a command that is not SET" do
      lint.("MSG Latitude is [$Latitude]\n").should.be.empty
    end

    it "says nothing about comments" do
      lint.("# SET $Latitude 45.42\n").should.be.empty
    end
  end

  it "reports at error severity" do
    lint.("SET $Latitude 45.42\n").first.severity.should == "error"
  end
end
