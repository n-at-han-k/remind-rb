# frozen_string_literal: true

require "open3"
require "tempfile"

require_relative "../rule"

module RemLint
  module Rules
    # Remind's own diagnostics, folded into the linter's output.
    #
    # puppet-lint draws the line here and it is the right line: a linter
    # validates style, and for "is this even valid" you run the real parser.
    # Remind has no parse-only mode, so the real parser is Remind, and running
    # it means running the file.
    #
    # THIS RULE IS OFF BY DEFAULT, and stays off unless someone turns it on,
    # because of what running the file means:
    #
    #   INCLUDE and INCLUDECMD read -- and INCLUDECMD executes -- other things
    #   RUN reminders shell out
    #
    # `-r` is passed to disable RUN directives, `-q` to keep timed reminders
    # out of the queue, and `-n` to ask only for next occurrences. That covers
    # the RUN half. It does not cover INCLUDECMD, so turn this on for files you
    # trust and leave it off for files you do not.
    #
    # When `remind` is not on PATH the rule reports nothing rather than
    # failing: a linter that cannot run on a machine without Remind installed
    # is a linter that cannot run in CI.
    class Syntax < Rule
      DEFAULT_COMMAND = "remind"

      # `file(12): Some message` and `file(12:14): Some message`, the two forms
      # src/main.c prints depending on whether the command spanned lines.
      DIAGNOSTIC = /\A(?<file>[^(]+)\((?<line>\d+)(?::(?<end_line>\d+))?\):\s*(?<message>.*)\z/

      # Remind labels its own non-fatal diagnostics -- "Warning: Missing ENDIF"
      # and friends -- so they are relayed as warnings rather than promoted to
      # errors by this rule's configured severity.
      WARNING = /\Awarning\b/i

      def self.enabled_by_default?
        false
      end

      def self.default_severity
        "error"
      end

      def self.description
        "Diagnostics from running the file through Remind itself (off by default)."
      end

      def check
        command = option("Command", DEFAULT_COMMAND)

        if executable?(command)
          run_remind(command)
        end
      end

      private

        def executable?(command)
          ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).any? do |directory|
            File.executable?(File.join(directory, command))
          end
        end

        # The source is written out rather than piped, because a heredoc's
        # Remind is only part of its file and Remind must not see the shell
        # around it. Line numbers come back relative to the temporary file and
        # are shifted onto the real one.
        def run_remind(command)
          Tempfile.create(["remlint", ".rem"]) do |file|
            file.write(document.source.text)
            file.flush

            report(capture(command, file.path))
          end
        end

        def capture(command, path)
          output, _status = Open3.capture2e(
            command,
            "-n",
            "-r",
            "-q",
            path,
          )

          output
        rescue SystemCallError => error
          "#{path}(1): could not run #{command}: #{error.message}"
        end

        def report(output)
          output.each_line do |raw|
            match = raw.chomp.match(DIAGNOSTIC)

            if match
              relay(match)
            end
          end
        end

        def relay(match)
          message = match[:message].strip

          offend(shifted(match[:line]), message, severity: graded(message))
        end

        # nil means "use whatever the configuration says", which is what an
        # unlabelled diagnostic gets.
        def graded(message)
          if message.match?(WARNING)
            "warning"
          end
        end

        def shifted(line)
          Integer(line) + document.line_offset
        end
    end
  end
end

__END__

require_relative "../document"

describe "RemLint::Rules::Syntax" do
  lint = proc do |text, config = {}|
    source = RemLint::Source.new(path: "t.rem", text: text)

    RemLint::Rules::Syntax.new(config).run(RemLint::Document.new(source))
  end

  it "is off unless the configuration asks for it" do
    RemLint::Rules::Syntax.enabled_by_default?.should.be.false
  end

  it "reports nothing when the configured command is not on PATH" do
    lint.("this is not valid remind at all\n", "Command" => "definitely-not-installed").should.be.empty
  end

  describe "parsing Remind's diagnostics" do
    # A stub that prints what Remind prints, so the parsing is tested without
    # requiring Remind to be installed wherever the suite runs.
    stub = proc do |output|
      directory = Dir.mktmpdir("remlint-spec")
      path = File.join(directory, "fake-remind")

      File.write(path, "#!/bin/sh\ncat <<'DIAGNOSTICS'\n#{output}\nDIAGNOSTICS\n")
      File.chmod(0o755, path)
      ENV["PATH"] = "#{directory}#{File::PATH_SEPARATOR}#{ENV.fetch('PATH')}"

      "fake-remind"
    end

    it "turns a single-line diagnostic into an offence" do
      command = stub.("/tmp/x.rem(3): Missing ']'")
      offenses = lint.("MSG [x\n", "Command" => command)

      offenses.length.should == 1
      offenses.first.line.should == 3
      offenses.first.message.should == "Missing ']'"
    end

    it "takes the first line of a diagnostic that names a line range" do
      command = stub.("/tmp/x.rem(3:5): Missing ')'")

      lint.("MSG hi\n", "Command" => command).first.line.should == 3
    end

    it "reports every diagnostic Remind prints" do
      command = stub.("/tmp/x.rem(1): First\n/tmp/x.rem(2): Second")

      lint.("MSG hi\n", "Command" => command).map(&:line).should == [1, 2]
    end

    it "ignores output that is not a diagnostic" do
      command = stub.("MSG hi\nsomething else entirely")

      lint.("MSG hi\n", "Command" => command).should.be.empty
    end

    it "shifts a heredoc's diagnostics onto the enclosing file" do
      command = stub.("/tmp/x.rem(2): Missing ']'")
      source = RemLint::Source.new(path: "astro", text: "MSG hi\nMSG [x\n", line_offset: 12)
      rule = RemLint::Rules::Syntax.new("Command" => command)

      rule.run(RemLint::Document.new(source)).first.line.should == 14
    end

    it "reports at error severity" do
      command = stub.("/tmp/x.rem(1): Missing ']'")

      lint.("MSG [x\n", "Command" => command).first.severity.should == "error"
    end

    it "relays a diagnostic Remind labelled a warning as a warning" do
      command = stub.("/tmp/x.rem(1): Warning: Missing ENDIF")
      offense = lint.("IF a\n", "Command" => command).first

      offense.severity.should == "warning"
      offense.message.should == "Warning: Missing ENDIF"
    end
  end
end
