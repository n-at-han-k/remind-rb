# frozen_string_literal: true

require_relative "../rule"

module RemLint
  module Rules
    # A function that shells out, defined while `RUN` is off.
    #
    # Remind binds the `RUN` permission when a function is *defined*, not when
    # it is called. `userfns.c` stores the flag on the function
    # (`if (RunDisabled) func->run_disabled = 1`) and `expr.c` puts it back on
    # every call (`if (f->run_disabled) RunDisabled |= RUN_UF`). So:
    #
    #   RUN OFF
    #   FSET listing() shell("ls")
    #   RUN ON
    #   MSG [listing()]           # RUN disabled
    #
    # The function is defined in the sandbox and stays in it for good. Nothing
    # about the definition looks wrong, the `RUN ON` above the call looks like
    # it should be enough, and the error arrives from the call site -- which is
    # the one place the mistake is not.
    #
    # `shell()` is the only builtin that needs the permission (`funcs.c:2545`);
    # `INCLUDECMD` needs it too but is a command, not something a function can
    # contain.
    class ShellUseWhileRunDisabled < Rule
      SHELL = "shell"

      ON = "ON"
      OFF = "OFF"

      def self.default_severity
        "error"
      end

      def self.description
        "A function calling shell(), defined between RUN OFF and RUN ON."
      end

      def check
        disabled = false

        document.code_commands.each do |command|
          directive = run_directive(command)

          if directive
            disabled = directive == OFF
          elsif disabled
            check_definition(command)
          end
        end
      end

      private

        # `RUN ON` / `RUN OFF` is a directive; any other `RUN` is a reminder
        # that shells out. `DoRun` accepts exactly these two words, in any case.
        def run_directive(command)
          word = command.args.strip.upcase

          if command.keyword?("RUN") && (word == ON || word == OFF)
            word
          end
        end

        def check_definition(command)
          if command.keyword?("FSET")
            shell_calls(command).each do |token|
              offend_at(command.logical_line, token.offset, message)
            end
          end
        end

        def shell_calls(command)
          document.tokens_for(command.logical_line).select do |token|
            token.type == :function && token.value.casecmp?(SHELL)
          end
        end

        def message
          "`shell()` in a function defined while `RUN` is off: the permission " \
          "is bound here, not at the call, so this fails even after `RUN ON`"
        end
    end
  end
end

__END__

require_relative "../document"

describe "RemLint::Rules::ShellUseWhileRunDisabled" do
  lint = proc do |text|
    source = RemLint::Source.new(path: "t.rem", text: text)

    RemLint::Rules::ShellUseWhileRunDisabled.new.run(RemLint::Document.new(source))
  end

  it "reports a shell() function defined after RUN OFF" do
    offenses = lint.(%(RUN OFF\nFSET listing() shell("ls")\nRUN ON\n))

    offenses.length.should == 1
    offenses.first.line.should == 2
    offenses.first.message.should.match(/bound here, not at the call/)
  end

  it "accepts the same definition before RUN OFF" do
    lint.(%(FSET listing() shell("ls")\nRUN OFF\n)).should.be.empty
  end

  it "accepts the same definition after RUN is turned back on" do
    lint.(%(RUN OFF\nRUN ON\nFSET listing() shell("ls")\n)).should.be.empty
  end

  it "accepts a file that never turns RUN off" do
    lint.(%(FSET listing() shell("ls")\n)).should.be.empty
  end

  it "reports every offending definition in the disabled span" do
    text = %(RUN OFF\nFSET a() shell("ls")\nFSET b() shell("date")\nRUN ON\n)

    lint.(text).map(&:line).should == [2, 3]
  end

  it "reports two calls in one definition" do
    lint.(%(RUN OFF\nFSET a() shell("ls") + shell("date")\n)).length.should == 2
  end

  it "matches RUN OFF whatever its case" do
    lint.(%(run off\nFSET a() shell("ls")\n)).length.should == 1
  end

  it "matches shell whatever its case" do
    lint.(%(RUN OFF\nFSET a() SHELL("ls")\n)).length.should == 1
  end

  it "points at the call" do
    text = %(RUN OFF\nFSET listing() shell("ls")\n)

    lint.(text).first.column.should == %(FSET listing() shell("ls")).index("shell") + 1
  end

  describe "what it leaves alone" do
    it "says nothing about a function that does not shell out" do
      lint.("RUN OFF\nFSET double(x) x * 2\n").should.be.empty
    end

    it "says nothing about a RUN reminder, which is not a directive" do
      # `RUN OFF` is the directive; `RUN echo off` is a reminder that runs a
      # command, and it does not disable anything.
      lint.(%(REM 1 Jan RUN echo off\nFSET a() shell("ls")\n)).should.be.empty
    end

    it "does not read a bare RUN reminder as a directive" do
      lint.(%(RUN echo hello\nFSET a() shell("ls")\n)).should.be.empty
    end

    it "says nothing about a shell() call outside a definition" do
      # That one fails visibly, at the point it is written.
      lint.(%(RUN OFF\nSET x shell("ls")\n)).should.be.empty
    end

    it "says nothing about comments" do
      lint.(%(RUN OFF\n# FSET a() shell("ls")\n)).should.be.empty
    end
  end

  it "reports at error severity" do
    lint.(%(RUN OFF\nFSET a() shell("ls")\n)).first.severity.should == "error"
  end
end
