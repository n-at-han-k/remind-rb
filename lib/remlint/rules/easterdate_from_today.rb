# frozen_string_literal: true

require_relative "../rule"

module RemLint
  module Rules
    # `easterdate(today())` in a trigger that adds an offset.
    #
    # `easterdate(date)` returns the *next* Easter on or after that date. So on
    # Easter Sunday it returns today, and on Easter Monday it returns Easter of
    # the following year. A reminder written
    #
    #   REM [easterdate(today())+1] MSG Easter Monday
    #
    # therefore never triggers: on Easter Monday the expression has already
    # jumped a year ahead, and the day it names is 364 days away.
    #
    # `easterdate(year)` -- the integer form -- returns Easter of that year and
    # does not move, which is why the fix is `easterdate(year(today()))`.
    #
    # The same reasoning applies to `orthodoxeaster`, which has the same two
    # forms.
    class EasterdateFromToday < Rule
      FUNCTIONS = %w[easterdate orthodoxeaster].freeze

      TODAY = %w[today now realtoday].freeze

      def self.default_severity
        "warning"
      end

      def self.description
        "easterdate(today()) in a trigger with an offset, which skips a year on the day."
      end

      def check
        document.code_commands.each do |command|
          if offset_trigger?(command)
            check_calls(command)
          end
        end
      end

      private

        # An offset only matters inside the trigger, and only when there is one
        # to matter: `REM [easterdate(today())] MSG Easter` is correct.
        def offset_trigger?(command)
          trigger = document.trigger_for(command)
          limit = trigger.body_offset || command.text.length
          tokens = document.tokens_for(command.logical_line)

          trigger.triggered? && tokens.any? { |token| offset?(token, limit) }
        end

        def offset?(token, limit)
          token.offset < limit && token.type == :other && ["+", "-"].include?(token.value)
        end

        def check_calls(command)
          tokens = document.tokens_for(command.logical_line)

          tokens.each_index do |index|
            if easter_of_today?(tokens, index)
              offend_at(command.logical_line, tokens[index].offset, message(tokens[index]))
            end
          end
        end

        # `easterdate ( today ( ) )` -- the date form, fed the moving date.
        def easter_of_today?(tokens, index)
          window = tokens[index, 4]

          window&.length == 4 &&
            window[0].type == :function && FUNCTIONS.include?(window[0].value.downcase) &&
            window[1].type == :lparen &&
            window[2].type == :function && TODAY.include?(window[2].value.downcase) &&
            window[3].type == :lparen
        end

        def message(token)
          "`#{token.value}(today())` returns *next* Easter, so on the day itself it " \
          "jumps a year ahead and the offset never triggers; pass the year instead, " \
          "as `#{token.value}(year(today()))`"
        end
    end
  end
end

__END__

require_relative "../document"

describe "RemLint::Rules::EasterdateFromToday" do
  lint = proc do |text|
    source = RemLint::Source.new(path: "t.rem", text: text)

    RemLint::Rules::EasterdateFromToday.new.run(RemLint::Document.new(source))
  end

  messages = proc { |text| lint.(text).map(&:message) }

  it "reports the date form with an offset" do
    messages.("REM [easterdate(today())+1] MSG Easter Monday\n").first.should.match(
      /jumps a year ahead and the offset never triggers/,
    )
  end

  it "suggests the year form" do
    messages.("REM [easterdate(today())+1] MSG hi\n").first.should.match(
      /as `easterdate\(year\(today\(\)\)\)`/,
    )
  end

  it "reports a negative offset too" do
    lint.("REM [easterdate(today())-2] MSG Good Friday\n").length.should == 1
  end

  it "reports orthodoxeaster the same way" do
    messages.("REM [orthodoxeaster(today())+1] MSG hi\n").first.should.match(/orthodoxeaster/)
  end

  it "accepts the date form with no offset" do
    lint.("REM [easterdate(today())] MSG Easter Sunday\n").should.be.empty
  end

  it "accepts the year form, which does not move" do
    lint.("REM [easterdate(year(today()))+1] MSG Easter Monday\n").should.be.empty
  end

  it "accepts an offset with no easterdate at all" do
    lint.("REM [trigger(today())+1] MSG hi\n").should.be.empty
  end

  it "says nothing about an offset in the body" do
    lint.("REM [easterdate(today())] MSG Easter, +1 day to go\n").should.be.empty
  end

  it "says nothing about a SET, which has no trigger" do
    lint.("SET a easterdate(today())+1\n").should.be.empty
  end

  it "matches the function name case-insensitively" do
    lint.("REM [EASTERDATE(TODAY())+1] MSG hi\n").length.should == 1
  end

  it "says nothing about comments" do
    lint.("# REM [easterdate(today())+1] MSG hi\n").should.be.empty
  end

  it "points at the call" do
    text = "REM [easterdate(today())+1] MSG hi\n"

    lint.(text).first.column.should == text.index("easterdate") + 1
  end

  it "reports at warning severity" do
    lint.("REM [easterdate(today())+1] MSG hi\n").first.severity.should == "warning"
  end
end
