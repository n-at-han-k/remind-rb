# frozen_string_literal: true

require_relative "../rule"
require_relative "../vocabulary"

module RemLint
  module Rules
    # Calls that pass the wrong number of arguments.
    #
    # The arities come from Remind's own function table (src/funcs.c), so this
    # is not a guess about what `ampm` accepts -- it is what `ampm` accepts.
    # `defs.rem` defines fifteen-odd helpers and calls them throughout, and
    # `astro` threads `sunrise($T+1)` through four separate heredocs; getting an
    # argument count wrong there fails at trigger time, on the one day of the
    # year the reminder fires.
    #
    # Two deliberate silences:
    #
    # UNKNOWN FUNCTIONS ARE NOT REPORTED. A reminder file's helpers usually
    # arrive through `INCLUDE`, and this rule reads one file. Complaining about
    # every call into `$SysInclude` would drown the calls it can actually check.
    #
    # A FUNCTION DEFINED LATER IN THE FILE STILL COUNTS. Definitions are
    # collected in a first pass, because `FSET` at the bottom of a file is
    # legal and common. A call is checked against the definition in force where
    # it sits -- the nearest one above it -- and only falls back to a later
    # definition when there is nothing above. Remind's own `tests/test.rem`
    # defines `g(x, y)` on line 356 and redefines it as `g(x)` on line 1545;
    # taking the last definition file-wide would report all three of the
    # perfectly correct two-argument calls in between.
    class FunctionArity < Rule
      # `FSET name(a, b)` -- the parameter list ends at the first `)`, since
      # Remind's parameters are plain names.
      DEFINITION = /\A\s*(?<name>[A-Za-z_]\w*)\s*\((?<params>[^)]*)\)/

      def self.default_severity
        "error"
      end

      def self.description
        "Calls that pass more or fewer arguments than the function takes."
      end

      def check
        @definitions = collect_definitions

        document.logical_lines.each_with_index do |logical_line, index|
          command = document.commands[index]

          if command.code?
            check_calls(logical_line, command)
          end
        end
      end

      private

        # Every `FSET` in the file, in order: [name, line, parameter count].
        # Kept as a list rather than a hash because a file may define the same
        # name twice and which one applies depends on where you are.
        def collect_definitions
          document.code_commands.filter_map do |command|
            match = command.keyword?("FSET") && command.args.match(DEFINITION)

            if match
              [match[:name].downcase, command.line, count_parameters(match[:params])]
            end
          end
        end

        # The definition in force at `line`: the nearest one at or above it,
        # or -- for a helper defined at the bottom of the file -- the first one
        # below.
        def definition_at(name, line)
          candidates = @definitions.select { |defined_name, _line, _arity| defined_name == name }
          above = candidates.select { |_name, defined_line, _arity| defined_line <= line }.last
          chosen = above || candidates.first

          chosen&.last
        end

        def count_parameters(params)
          if params.strip.empty?
            0
          else
            params.split(",").length
          end
        end

        def check_calls(logical_line, command)
          tokens = document.tokens_for(logical_line)
          from = body_offset(command)

          tokens.each_with_index do |token, index|
            if token.type == :function && token.offset >= from
              check_call(logical_line, tokens, index)
            end
          end
        end

        # `FSET greet(a, b) ...` opens with something that lexes exactly like a
        # call to `greet` -- it is the definition's parameter list. Skipping
        # past it stops every definition reporting itself, which is what makes
        # a redefinition (`FSET f(a)` then `FSET f(a, b)`) legal rather than an
        # offence against its own later self.
        def body_offset(command)
          match = command.keyword?("FSET") && command.args.match(DEFINITION)

          if match
            command.args_offset + match.end(0)
          else
            0
          end
        end

        def check_call(logical_line, tokens, index)
          token = tokens[index]
          line, _column = logical_line.position_at(token.offset)
          expected = arity_of(token.value, line)
          actual = count_arguments(tokens, index + 1)

          if !expected.nil? && !actual.nil? && !acceptable?(expected, actual)
            offend_at(logical_line, token.offset, arity_message(token.value, expected, actual))
          end
        end

        # A builtin's arity comes from Remind's table; a local `FSET` fixes an
        # exact count. Anything else is out of scope and returns nil.
        def arity_of(name, line)
          builtin = Vocabulary.function(name)

          if builtin
            builtin
          else
            definition_at(name.downcase, line)
          end
        end

        def acceptable?(expected, actual)
          if expected.is_a?(Integer)
            expected == actual
          else
            expected.accepts?(actual)
          end
        end

        def arity_message(name, expected, actual)
          if expected.is_a?(Integer)
            wanted = expected.to_s
          else
            wanted = expected.arity_description
          end

          "`#{name}` takes #{wanted} #{pluralise(wanted)}, given #{actual}"
        end

        # "1" and "at least 1" are singular; "3" and "1 to 4" are not. The
        # number the phrase ends on is the one being counted.
        def pluralise(wanted)
          if wanted[/\d+\z/] == "1"
            "argument"
          else
            "arguments"
          end
        end

        # Count top-level commas between the call's parentheses. Returns nil if
        # the call is not parenthesised or never closes -- an unclosed call is
        # UnbalancedDelimiters' offence, and guessing an argument count from a
        # broken call would report a second, invented one.
        def count_arguments(tokens, open_index)
          open = tokens[open_index]

          if open.nil? || open.type != :lparen
            nil
          else
            walk_arguments(tokens, open_index)
          end
        end

        def walk_arguments(tokens, open_index)
          depth = 0
          commas = 0
          empty = true
          closed = false
          cursor = open_index

          while cursor < tokens.length && !closed
            token = tokens[cursor]
            depth, commas, empty, closed = step(
              token,
              depth,
              commas,
              empty,
              closed,
            )
            cursor += 1
          end

          arguments(closed, commas, empty)
        end

        def step(token, depth, commas, empty, closed)
          case token.type
          when :lparen, :lbracket
            [depth + 1, commas, empty, closed]
          when :rparen, :rbracket
            close_or_descend(
              token,
              depth,
              commas,
              empty,
            )
          when :comma
            [depth, depth == 1 ? commas + 1 : commas, empty, closed]
          else
            [depth, commas, depth == 1 ? false : empty, closed]
          end
        end

        def close_or_descend(_token, depth, commas, empty)
          if depth == 1
            [depth - 1, commas, empty, true]
          else
            [depth - 1, commas, empty, false]
          end
        end

        # `f()` is zero arguments; `f(a, b)` is commas plus one. A call that
        # never closed yields nil so nothing is reported for it.
        def arguments(closed, commas, empty)
          if !closed
            nil
          elsif empty && commas.zero?
            0
          else
            commas + 1
          end
        end
    end
  end
end

__END__

require_relative "../document"

describe "RemLint::Rules::FunctionArity" do
  lint = proc do |text|
    source = RemLint::Source.new(path: "t.rem", text: text)

    RemLint::Rules::FunctionArity.new.run(RemLint::Document.new(source))
  end

  messages = proc { |text| lint.(text).map(&:message) }

  describe "builtin functions" do
    it "accepts a call with the right number of arguments" do
      lint.("MSG [abs(-1)]\n").should.be.empty
    end

    it "reports too many arguments" do
      messages.("MSG [abs(1, 2)]\n").should == ["`abs` takes 1 argument, given 2"]
    end

    it "reports too few arguments" do
      messages.("MSG [date(2026, 1)]\n").should == ["`date` takes 3 arguments, given 2"]
    end

    it "accepts anything inside an optional range" do
      lint.("MSG [ampm(1)] [ampm(1,2)] [ampm(1,2,3,4)]\n").should.be.empty
    end

    it "reports past the top of an optional range" do
      messages.("MSG [ampm(1,2,3,4,5)]\n").should == ["`ampm` takes 1 to 4 arguments, given 5"]
    end

    it "accepts any count for a variadic function" do
      lint.("MSG [char(65, 66, 67, 68)]\n").should.be.empty
    end

    it "reports below a variadic function's minimum" do
      messages.("MSG [char()]\n").should == ["`char` takes at least 1 argument, given 0"]
    end

    it "accepts a zero-argument call" do
      lint.("MSG [version()] [today()]\n").should.be.empty
    end

    it "reports arguments given to a function that takes none" do
      messages.("MSG [version(1)]\n").should == ["`version` takes 0 arguments, given 1"]
    end

    it "matches the function name case-insensitively, as Remind does" do
      messages.("MSG [ABS(1, 2)]\n").should == ["`ABS` takes 1 argument, given 2"]
    end
  end

  describe "nested calls" do
    it "counts arguments at the right depth" do
      lint.("MSG [max(abs(-1), abs(-2))]\n").should.be.empty
    end

    it "reports the inner call, not the outer one" do
      messages.("MSG [max(abs(-1, 9), 2)]\n").should == ["`abs` takes 1 argument, given 2"]
    end

    it "does not count a comma inside a nested call as its own argument" do
      lint.("MSG [ansicolor(0, 255, 0) + center(\"x\")]\n").should.be.empty
    end

    it "does not count a comma inside a string as an argument separator" do
      lint.(%(MSG [abs("a, b, c")]\n)).should.be.empty
    end
  end

  describe "functions the file defines itself" do
    it "checks a call against its FSET" do
      messages.("FSET greet(a, b) a + b\nMSG [greet(1)]\n").should ==
        ["`greet` takes 2 arguments, given 1"]
    end

    it "accepts a correct call" do
      lint.("FSET greet(a, b) a + b\nMSG [greet(1, 2)]\n").should.be.empty
    end

    it "accepts a definition that appears after the call" do
      lint.("MSG [greet(1, 2)]\nFSET greet(a, b) a + b\n").should.be.empty
    end

    it "handles a nullary definition" do
      messages.("FSET now() today()\nMSG [now(1)]\n").should == ["`now` takes 0 arguments, given 1"]
    end

    it "does not treat the definition's own parameter list as a call" do
      lint.("FSET center(x) pad(\"\", \" \", (columns() - columns(x))/2) + x\n").should.be.empty
    end

    it "checks a call against the definition in force above it" do
      # Remind's own tests/test.rem does exactly this: g(x, y) high up, g(x)
      # much further down, with correct two-argument calls in between.
      text = "FSET g(a, b) a + b\nMSG [g(1, 2)]\nFSET g(a) a\nMSG [g(1)]\n"

      lint.(text).should.be.empty
    end

    it "reports a call that matches only the other definition" do
      text = "FSET g(a, b) a + b\nMSG [g(1)]\nFSET g(a) a\n"

      messages.(text).should == ["`g` takes 2 arguments, given 1"]
    end
  end

  describe "what it stays quiet about" do
    it "says nothing about a function it has never heard of" do
      # Helpers usually arrive through INCLUDE, which this rule cannot see.
      lint.("MSG [helper_from_include(1, 2, 3)]\n").should.be.empty
    end

    it "says nothing about a bare name that is not a call" do
      lint.("MSG [abs]\n").should.be.empty
    end

    it "says nothing about a call that never closes" do
      # That is UnbalancedDelimiters' offence; counting arguments in a broken
      # call would invent a second one.
      lint.("MSG [abs(1, 2\n").should.be.empty
    end

    it "says nothing about comments" do
      lint.("# call abs(1, 2) somewhere\n").should.be.empty
    end
  end

  it "reports the physical line a call sits on inside a continuation" do
    offense = lint.("SET x 1 + \\\n    abs(1, 2)\n").first

    offense.line.should == 2
    offense.column.should == 5
  end

  it "reports at error severity" do
    lint.("MSG [abs(1, 2)]\n").first.severity.should == "error"
  end
end
