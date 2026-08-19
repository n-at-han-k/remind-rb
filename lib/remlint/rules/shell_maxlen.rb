# frozen_string_literal: true

require_relative "../rule"

module RemLint
  module Rules
    # `shell()` given a maximum length that returns nothing.
    #
    # `shell(cmd)` reads up to 511 characters of the command's output;
    # `shell(cmd, n)` reads up to *n*. A zero returns the empty string, and a
    # command that produced no output returns the empty string too -- so
    # `shell(cmd, 0)` is indistinguishable from a command that did not work,
    # and debugging starts in the wrong place entirely.
    #
    # A negative *n* is the documented sentinel for "no limit", so only zero is
    # reported.
    class ShellMaxlen < Rule
      SHELL = "shell"

      def self.default_severity
        "warning"
      end

      def self.description
        "shell() given a maximum length of zero, which always returns nothing."
      end

      def check
        document.logical_lines.each_with_index do |logical_line, index|
          if document.commands[index].code?
            check_line(logical_line)
          end
        end
      end

      private

        def check_line(logical_line)
          tokens = document.tokens_for(logical_line)

          tokens.each_index do |index|
            if call?(tokens, index)
              check_call(logical_line, tokens, index)
            end
          end
        end

        def call?(tokens, index)
          tokens[index].type == :function &&
            tokens[index].value.casecmp?(SHELL) &&
            tokens[index + 1]&.type == :lparen
        end

        # The second argument, when it is written out as a literal zero. The
        # walk stops at the first top-level comma's operand, so a nested call
        # in the first argument does not confuse it.
        def check_call(logical_line, tokens, index)
          zero = second_argument(tokens, index + 1)

          if zero
            offend_at(
              logical_line,
              zero.offset,
              "`shell(..., 0)` returns the empty string whatever the command prints, " \
              "which looks exactly like a command that produced nothing",
            )
          end
        end

        def second_argument(tokens, open_index)
          comma = top_level_comma(tokens, open_index)
          argument = comma && tokens[comma + 1]

          if argument&.type == :number && argument.value.to_i.zero? &&
             tokens[comma + 2]&.type == :rparen
            argument
          end
        end

        def top_level_comma(tokens, open_index)
          depth = 0
          cursor = open_index

          while cursor < tokens.length
            depth = depth_after(tokens[cursor], depth)

            if depth.zero?
              break
            end

            if depth == 1 && tokens[cursor].type == :comma
              break
            end

            cursor += 1
          end

          if tokens[cursor]&.type == :comma
            cursor
          end
        end

        def depth_after(token, depth)
          case token.type
          when :lparen, :lbracket then depth + 1
          when :rparen, :rbracket then depth - 1
          else depth
          end
        end
    end
  end
end

__END__

require_relative "../document"

describe "RemLint::Rules::ShellMaxlen" do
  lint = proc do |text|
    source = RemLint::Source.new(path: "t.rem", text: text)

    RemLint::Rules::ShellMaxlen.new.run(RemLint::Document.new(source))
  end

  it "reports a zero maximum length" do
    lint.(%(SET a shell("ls", 0)\n)).first.message.should.match(/returns the empty string/)
  end

  it "accepts the one-argument form" do
    lint.(%(SET a shell("ls")\n)).should.be.empty
  end

  it "accepts a positive maximum length" do
    lint.(%(SET a shell("ls", 1024)\n)).should.be.empty
  end

  it "accepts the negative sentinel" do
    lint.(%(SET a shell("ls", -1)\n)).should.be.empty
  end

  it "is not confused by a comma inside the command" do
    lint.(%(SET a shell("echo a,b")\n)).should.be.empty
  end

  it "is not confused by a nested call in the first argument" do
    lint.(%(SET a shell(join("ls", "-l"), 1024)\n)).should.be.empty
  end

  it "matches the function name case-insensitively" do
    lint.(%(SET a SHELL("ls", 0)\n)).length.should == 1
  end

  it "points at the zero" do
    text = %(SET a shell("ls", 0)\n)

    lint.(text).first.column.should == text.rindex("0") + 1
  end

  it "says nothing about another function with a zero argument" do
    lint.("SET a max(1, 0)\n").should.be.empty
  end

  it "says nothing about comments" do
    lint.(%(# SET a shell("ls", 0)\n)).should.be.empty
  end

  it "reports at warning severity" do
    lint.(%(SET a shell("ls", 0)\n)).first.severity.should == "warning"
  end
end
