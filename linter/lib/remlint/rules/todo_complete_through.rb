# frozen_string_literal: true

require_relative "../rule"

module RemLint
  module Rules
    # A `TODO` with no `COMPLETE-THROUGH`.
    #
    # `COMPLETE-THROUGH` tells Remind the date up to which the task has been
    # done, and it is the starting point of a TODO's entire trigger
    # calculation. Without it the algorithm starts at Remind's epoch --
    # 1990-01-01 -- so the TODO is overdue by several decades the first time it
    # runs, and stays that way.
    #
    # It is not an error, and it produces output rather than silence, which is
    # what makes it hard to read as a mistake: the reminder appears, screaming,
    # and looks like a problem with the task rather than with the clause that
    # was meant to be filled in and never was.
    class TodoCompleteThrough < Rule
      def self.default_severity
        "warning"
      end

      def self.description
        "A TODO reminder with no COMPLETE-THROUGH to start its calculation from."
      end

      def check
        document.code_commands.each do |command|
          trigger = document.trigger_for(command)

          if trigger.include?("TODO") && !trigger.include?("COMPLETE-THROUGH")
            report(command, trigger)
          end
        end
      end

      private

        def report(command, trigger)
          offend_at(
            command.logical_line,
            trigger.find("TODO").offset,
            "a `TODO` with no `COMPLETE-THROUGH` starts its calculation at Remind's " \
            "epoch, 1990-01-01, so it is overdue by decades on its first run",
          )
        end
    end
  end
end

__END__

require_relative "../document"

describe "RemLint::Rules::TodoCompleteThrough" do
  lint = proc do |text|
    source = RemLint::Source.new(path: "t.rem", text: text)

    RemLint::Rules::TodoCompleteThrough.new.run(RemLint::Document.new(source))
  end

  it "reports a TODO with no COMPLETE-THROUGH" do
    lint.("REM 1 TODO MSG File the accounts\n").first.message.should.match(
      /overdue by decades on its first run/,
    )
  end

  it "accepts a TODO that has one" do
    lint.("REM 1 TODO COMPLETE-THROUGH 2026-01-01 MSG File the accounts\n").should.be.empty
  end

  it "accepts the clauses in either order" do
    lint.("REM 1 COMPLETE-THROUGH 2026-01-01 TODO MSG File\n").should.be.empty
  end

  it "says nothing about a reminder that is not a TODO" do
    lint.("REM 1 MSG File the accounts\n").should.be.empty
  end

  it "points at the TODO clause" do
    text = "REM 1 TODO MSG File\n"

    lint.(text).first.column.should == text.index("TODO") + 1
  end

  it "does not read the word todo out of a body" do
    lint.("REM 1 MSG add this to the todo list\n").should.be.empty
  end

  it "says nothing about comments" do
    lint.("# REM 1 TODO MSG File\n").should.be.empty
  end

  it "reports at warning severity" do
    lint.("REM 1 TODO MSG File\n").first.severity.should == "warning"
  end
end
