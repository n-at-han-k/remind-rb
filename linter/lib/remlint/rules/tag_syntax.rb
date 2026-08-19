# frozen_string_literal: true

require_relative "../rule"

module RemLint
  module Rules
    # `TAG` values that will not survive the trip to a back-end.
    #
    # Tags are handed to the machine-readable back-ends as a comma-separated
    # list. A comma inside one tag therefore splits it into two tags nobody
    # wrote, and whitespace inside one ends it early. Neither is an error --
    # the reminder triggers, the tag is simply not the tag that was written,
    # and the mistake surfaces in whatever consumes the export.
    class TagSyntax < Rule
      FORBIDDEN = {
        ","  => "separates tags in the list back-ends receive",
        " "  => "ends the tag",
        "\t" => "ends the tag",
      }.freeze

      def self.default_severity
        "warning"
      end

      def self.description
        "A TAG value containing a comma or whitespace."
      end

      def check
        document.code_commands.each do |command|
          document.trigger_for(command).clauses.each do |clause|
            if clause.name == "TAG"
              check_tag(command, clause)
            end
          end
        end
      end

      private

        def check_tag(command, clause)
          value = quoted_value(command, clause)

          if value
            report(command, clause, value)
          end
        end

        # Only a quoted tag can carry a comma or a space in the first place --
        # an unquoted one is already ended by the whitespace, which the
        # tokeniser settles before this rule sees it.
        def quoted_value(command, clause)
          tokens = document.tokens_for(command.logical_line)
          token = tokens[clause.argument_index]

          if token&.type == :string
            token.value[1..-2]
          end
        end

        def report(command, clause, value)
          FORBIDDEN.each do |character, effect|
            if value.include?(character)
              offend_at(command.logical_line, clause.offset, message(value, character, effect))
            end
          end
        end

        def message(value, character, effect)
          if character == "\t"
            named = "a tab"
          else
            named = "`#{character}`"
          end

          "the tag `#{value}` contains #{named}, which #{effect}"
        end
    end
  end
end

__END__

require_relative "../document"

describe "RemLint::Rules::TagSyntax" do
  lint = proc do |text|
    source = RemLint::Source.new(path: "t.rem", text: text)

    RemLint::Rules::TagSyntax.new.run(RemLint::Document.new(source))
  end

  messages = proc { |text| lint.(text).map(&:message) }

  it "accepts a plain tag" do
    lint.(%(REM 1 Jan TAG "birthday" MSG hi\n)).should.be.empty
  end

  it "accepts an unquoted tag" do
    lint.("REM 1 Jan TAG birthday MSG hi\n").should.be.empty
  end

  it "accepts a tag with a hyphen or an underscore" do
    lint.(%(REM 1 Jan TAG "work-related_thing" MSG hi\n)).should.be.empty
  end

  it "reports a comma inside a tag" do
    messages.(%(REM 1 Jan TAG "work,home" MSG hi\n)).first.should ==
      "the tag `work,home` contains `,`, which separates tags in the list back-ends receive"
  end

  it "reports a space inside a tag" do
    messages.(%(REM 1 Jan TAG "work stuff" MSG hi\n)).first.should.match(/contains `.`, which ends the tag/)
  end

  it "reports a tab inside a tag" do
    messages.(%(REM 1 Jan TAG "work\tstuff" MSG hi\n)).first.should.match(/contains a tab/)
  end

  it "reports both faults in one tag" do
    lint.(%(REM 1 Jan TAG "a, b" MSG hi\n)).length.should == 2
  end

  it "points at the clause" do
    text = %(REM 1 Jan TAG "work,home" MSG hi\n)

    lint.(text).first.column.should == text.index("TAG") + 1
  end

  it "says nothing about a reminder with no TAG" do
    lint.("REM 1 Jan MSG hi\n").should.be.empty
  end

  it "does not read a tag out of a message body" do
    lint.(%(REM 1 Jan MSG the tag "a,b" is wrong\n)).should.be.empty
  end

  it "says nothing about comments" do
    lint.(%(# REM 1 Jan TAG "a,b" MSG hi\n)).should.be.empty
  end

  it "reports at warning severity" do
    lint.(%(REM 1 Jan TAG "a,b" MSG hi\n)).first.severity.should == "warning"
  end
end
