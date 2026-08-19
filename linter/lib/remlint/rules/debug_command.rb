# frozen_string_literal: true

require_relative "../rule"

module RemLint
  module Rules
    # `DEBUG` flags that do nothing, and `DEBUG` flags left switched on.
    #
    # `DoDebug` in src/main.c reads the argument character by character: `+`
    # turns flags on, `-` turns them off, and thirteen letters name a flag.
    # Anything else reaches a `default:` branch that warns -- but only at
    # warning level 05.02.03, so a script that has not raised the level gets a
    # debug session that quietly does nothing.
    #
    # The other half matters more in a repository than at a terminal. Debug
    # output is voluminous and goes to standard error, so a `DEBUG +x` that was
    # never matched by a `DEBUG -x` turns every later run into a trace log --
    # including the one under cron, which mails it to somebody.
    class DebugCommand < Rule
      # The flag letters `DoDebug` switches on, case-insensitive.
      FLAGS = %w[p e q s h x t v l f n u z].freeze

      SIGNS = %w[+ -].freeze

      def self.default_severity
        "warning"
      end

      def self.description
        "A DEBUG flag Remind does not define, or one switched on and never off."
      end

      def check
        left_on = {}

        document.code_commands.each do |command|
          if command.keyword?("DEBUG")
            scan(command, left_on)
          end
        end

        report_left_on(left_on)
      end

      private

        def scan(command, left_on)
          sign = "+"

          command.args.each_char.with_index do |character, index|
            sign = step(
              command,
              character,
              sign,
              index,
              left_on,
            )
          end
        end

        def step(command, character, sign, index, left_on)
          if SIGNS.include?(character)
            character
          elsif character.match?(/\s/)
            sign
          else
            record(
              command,
              character,
              sign,
              index,
              left_on,
            )
            sign
          end
        end

        def record(command, character, sign, index, left_on)
          if FLAGS.include?(character.downcase)
            track(
              command,
              character.downcase,
              sign,
              left_on,
            )
          else
            report_unknown(command, character, index)
          end
        end

        def track(command, flag, sign, left_on)
          if sign == "+"
            left_on[flag] ||= command
          else
            left_on.delete(flag)
          end
        end

        def report_unknown(command, character, index)
          offend(
            command.line,
            "`#{character}` is not a DEBUG flag; Remind defines #{FLAGS.join(', ')}",
            column: command.args_offset + index + 1,
          )
        end

        def report_left_on(left_on)
          left_on.each do |flag, command|
            offend(
              command.line,
              "`DEBUG +#{flag}` is never matched by a `DEBUG -#{flag}`; debug output " \
              "goes to standard error on every later run, including the one under cron",
              column: command.keyword_column,
            )
          end
        end
    end
  end
end

__END__

require_relative "../document"

describe "RemLint::Rules::DebugCommand" do
  lint = proc do |text|
    source = RemLint::Source.new(path: "t.rem", text: text)

    RemLint::Rules::DebugCommand.new.run(RemLint::Document.new(source))
  end

  messages = proc { |text| lint.(text).map(&:message) }

  describe "unknown flags" do
    it "reports a letter Remind does not define" do
      messages.("DEBUG +w\nDEBUG -w\n").first.should.match(/`w` is not a DEBUG flag/)
    end

    it "lists the flags Remind does define" do
      messages.("DEBUG +w\nDEBUG -w\n").first.should.match(/p, e, q, s, h, x, t, v, l, f, n, u, z/)
    end

    it "accepts every flag Remind defines" do
      lint.("DEBUG +peqshxtvlfnuz\nDEBUG -peqshxtvlfnuz\n").should.be.empty
    end

    it "accepts them in upper case" do
      lint.("DEBUG +X\nDEBUG -X\n").should.be.empty
    end
  end

  describe "flags left on" do
    it "reports a flag switched on and never off" do
      messages.("DEBUG +x\n").first.should.match(/never matched by a `DEBUG -x`/)
    end

    it "accepts a flag switched on and then off" do
      lint.("DEBUG +x\nMSG hi\nDEBUG -x\n").should.be.empty
    end

    it "accepts several flags switched on and off together" do
      lint.("DEBUG +xt\nMSG hi\nDEBUG -xt\n").should.be.empty
    end

    it "reports each flag left on" do
      lint.("DEBUG +xt\n").length.should == 2
    end

    it "handles a sign that applies to several letters" do
      lint.("DEBUG +xt -x\nDEBUG -t\n").should.be.empty
    end

    it "reports the line the flag was switched on" do
      lint.("MSG hi\nDEBUG +x\n").first.line.should == 2
    end
  end

  it "says nothing about a file with no DEBUG at all" do
    lint.("MSG hi\n").should.be.empty
  end

  it "says nothing about comments" do
    lint.("# DEBUG +w\n").should.be.empty
  end

  it "reports at warning severity" do
    lint.("DEBUG +x\n").first.severity.should == "warning"
  end
end
