# frozen_string_literal: true

require_relative "../rule"
require_relative "../vocabulary"

module RemLint
  module Rules
    # `SET` on a system variable that will not take it.
    #
    # Remind's table marks each variable modifiable or not and, for the integer
    # ones, carries the range it will accept (src/var.c SysVarArr). Writing to a
    # read-only variable is `E_CANT_MODIFY`; writing out of range is
    # `E_2LOW`/`E_2HIGH`. Both are decidable from the line alone whenever the
    # value is a literal, which is how these variables are almost always set:
    #
    #   SET $CalMode 1          $CalMode reports the mode, it does not set it
    #   SET $FormWidth 10       Remind accepts 20 to 500
    #
    # A computed value (`SET $FormWidth columns()`) is left alone: the rule
    # cannot know what it evaluates to, and guessing would be worse than
    # silence.
    class SystemVariableAssignment < Rule
      # `SET $Name value` -- and `UNSET $Name`, which is the same permission
      # question with no value attached.
      ASSIGNMENT = /\A(?<sigil>\$)(?<name>\w+)\s*(?<value>.*)\z/m

      INTEGER = /\A[+-]?\d+\z/

      def self.default_severity
        "error"
      end

      def self.description
        "SET on a read-only system variable, or with a value outside its range."
      end

      def check
        document.code_commands.each do |command|
          if command.keyword?("SET", "UNSET")
            check_assignment(command)
          end
        end
      end

      private

        def check_assignment(command)
          match = command.args.match(ASSIGNMENT)
          sysvar = match && Vocabulary.sysvar(match[:name])

          if sysvar
            check_permission(command, sysvar) || check_range(command, sysvar, match[:value])
          end
        end

        # Returns truthy when it reported, so a variable that cannot be written
        # at all is not also told its value is out of range.
        def check_permission(command, sysvar)
          unless sysvar.modifiable
            offend(
              command.line,
              "`$#{sysvar.name}` is read-only and cannot be #{verb(command)}",
              column: command.keyword_column,
            )
          end
        end

        def verb(command)
          if command.keyword?("UNSET")
            "unset"
          else
            "set"
          end
        end

        def check_range(command, sysvar, value)
          literal = integer_literal(value)

          if sysvar.bounded? && !literal.nil? && !sysvar.in_range?(literal)
            offend(
              command.line,
              "`$#{sysvar.name}` accepts #{sysvar.min} to #{sysvar.max}, given #{literal}",
              column: command.keyword_column,
            )
          end
        end

        def integer_literal(value)
          text = value.to_s.strip

          if text.match?(INTEGER)
            Integer(text)
          end
        end
    end
  end
end

__END__

require_relative "../document"

describe "RemLint::Rules::SystemVariableAssignment" do
  lint = proc do |text|
    source = RemLint::Source.new(path: "t.rem", text: text)

    RemLint::Rules::SystemVariableAssignment.new.run(RemLint::Document.new(source))
  end

  messages = proc { |text| lint.(text).map(&:message) }

  describe "assignments Remind accepts" do
    it "accepts a writable variable" do
      lint.("SET $AddBlankLines 0\n").should.be.empty
    end

    it "accepts a value at each end of the range" do
      lint.("SET $FormWidth 20\nSET $FormWidth 500\n").should.be.empty
    end

    it "accepts a negative value inside a range that allows one" do
      lint.("SET $MinsFromUTC -300\n").should.be.empty
    end

    it "accepts a string value for a string variable" do
      lint.(%(SET $Ago "ago"\n)).should.be.empty
    end

    it "matches the variable name case-insensitively" do
      lint.("SET $formwidth 100\n").should.be.empty
    end
  end

  describe "read-only variables" do
    it "reports a SET" do
      messages.("SET $CalMode 1\n").should == ["`$CalMode` is read-only and cannot be set"]
    end

    it "reports an UNSET with the right verb" do
      messages.("UNSET $CalMode\n").should == ["`$CalMode` is read-only and cannot be unset"]
    end

    it "does not also complain about the value" do
      lint.("SET $CalMode 99999\n").length.should == 1
    end

    it "points at the keyword" do
      lint.("   SET $CalMode 1\n").first.column.should == 4
    end
  end

  describe "values outside a variable's range" do
    it "reports one below the minimum" do
      messages.("SET $FormWidth 10\n").should == ["`$FormWidth` accepts 20 to 500, given 10"]
    end

    it "reports one above the maximum" do
      messages.("SET $FormWidth 900\n").should == ["`$FormWidth` accepts 20 to 500, given 900"]
    end

    it "reports a boolean variable given something other than 0 or 1" do
      messages.("SET $AddBlankLines 2\n").should == ["`$AddBlankLines` accepts 0 to 1, given 2"]
    end

    it "reports at error severity" do
      lint.("SET $FormWidth 10\n").first.severity.should == "error"
    end
  end

  describe "what it stays quiet about" do
    it "says nothing about a computed value it cannot evaluate" do
      lint.("SET $FormWidth columns()\n").should.be.empty
      lint.("SET $FormWidth [x]\n").should.be.empty
    end

    it "says nothing about a variable with no declared range" do
      lint.("SET $MaxSatIter 999999\n").should.be.empty
    end

    it "says nothing about an ordinary variable" do
      lint.("SET CalMode 1\n").should.be.empty
    end

    it "says nothing about a system variable it has never heard of" do
      # UnknownSystemVariable owns that offence.
      lint.("SET $Nope 1\n").should.be.empty
    end

    it "says nothing about a command that is not SET or UNSET" do
      lint.("MSG $CalMode is [$CalMode]\n").should.be.empty
    end
  end

  it "reports the line a continued assignment starts on" do
    lint.("SET $FormWidth \\\n    10\n").first.line.should == 1
  end
end
