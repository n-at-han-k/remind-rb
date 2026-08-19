# frozen_string_literal: true

require_relative "../rule"

module RemLint
  module Rules
    # A `TODO` with no `COMPLETE-THROUGH`.
    #
    # `COMPLETE-THROUGH` tells Remind the date up to which the task has been
    # done, and it is the starting point of a TODO's entire trigger
    # calculation. Without it the algorithm starts at Remind's epoch,
    # 1990-01-01, so the task is decades overdue.
    #
    # On its own that is harmless -- the TODO simply fires. It turns into a
    # defect the moment `MAX-OVERDUE` is added, because `MAX-OVERDUE` then
    # suppresses a task that is thirty-odd years past due, and the reminder
    # produces *nothing at all*:
    #
    #   REM TODO Mon MAX-OVERDUE 5 MSG x                      -> No reminders.
    #   REM TODO Mon COMPLETE-THROUGH 2026-01-01 MAX-OVERDUE 5 MSG x  -> fires
    #
    # So this reports the pair, not the missing clause alone. The book
    # described the failure as a reminder that arrives screaming; it is in fact
    # a reminder that never arrives, which is harder to notice and was worth
    # checking against the binary rather than taking on trust. Remind's own
    # `tests/` has twenty-one TODOs with no `COMPLETE-THROUGH` and they are all
    # fine, because none of them sets `MAX-OVERDUE`.
    class TodoCompleteThrough < Rule
      def self.default_severity
        "warning"
      end

      def self.description
        "A TODO with MAX-OVERDUE and no COMPLETE-THROUGH, which suppresses it entirely."
      end

      def check
        document.code_commands.each do |command|
          trigger = document.trigger_for(command)

          if trigger.include?("TODO") && trigger.include?("MAX-OVERDUE") &&
             !trigger.include?("COMPLETE-THROUGH")
            report(command, trigger)
          end
        end
      end

      private

        def report(command, trigger)
          offend_at(
            command.logical_line,
            trigger.find("TODO").offset,
            "this `TODO` has no `COMPLETE-THROUGH`, so its calculation starts at " \
            "Remind's epoch and the task is decades overdue -- and the `MAX-OVERDUE` " \
            "on the same command then suppresses it, so the reminder never appears",
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

  it "reports a TODO with MAX-OVERDUE and no COMPLETE-THROUGH" do
    lint.("REM Mon TODO MAX-OVERDUE 5 MSG File\n").first.message.should.match(
      /suppresses it, so the reminder never appears/,
    )
  end

  it "accepts one that has COMPLETE-THROUGH" do
    text = "REM Mon TODO COMPLETE-THROUGH 2026-01-01 MAX-OVERDUE 5 MSG File\n"

    lint.(text).should.be.empty
  end

  it "accepts the clauses in any order" do
    text = "REM Mon MAX-OVERDUE 5 COMPLETE-THROUGH 2026-01-01 TODO MSG File\n"

    lint.(text).should.be.empty
  end

  it "accepts a TODO with no MAX-OVERDUE, which simply fires" do
    # Remind's own tests/ has twenty-one of these and they all work.
    lint.("REM 1 TODO MSG File the accounts\n").should.be.empty
  end

  it "says nothing about MAX-OVERDUE without a TODO" do
    lint.("REM 1 MAX-OVERDUE 5 MSG File\n").should.be.empty
  end

  it "says nothing about a reminder that is not a TODO" do
    lint.("REM 1 MSG File the accounts\n").should.be.empty
  end

  it "points at the TODO clause" do
    text = "REM Mon TODO MAX-OVERDUE 5 MSG File\n"

    lint.(text).first.column.should == text.index("TODO") + 1
  end

  it "does not read the word todo out of a body" do
    lint.("REM 1 MSG add this to the todo list\n").should.be.empty
  end

  it "says nothing about comments" do
    lint.("# REM Mon TODO MAX-OVERDUE 5 MSG File\n").should.be.empty
  end

  it "reports at warning severity" do
    lint.("REM Mon TODO MAX-OVERDUE 5 MSG File\n").first.severity.should == "warning"
  end
end
