# frozen_string_literal: true

require_relative "../rule"

module RemLint
  module Rules
    # Callback functions defined with the wrong number of arguments.
    #
    # Remind calls a dozen or so functions by name and by shape. It does not
    # look them up and adapt -- it checks the arity and, if it does not match,
    # walks away:
    #
    #   UserFuncExists("msgprefix") == 1     src/dorem.c
    #   check_subst_args(func, 3)            src/dosubst.c
    #
    # So a `msgprefix(p, q)` is never called. Not called with an error, not
    # called with a warning: the prefix simply does not appear, and the
    # obvious conclusion is that the callback mechanism is broken rather than
    # that the signature is.
    #
    # This is `FunctionArity` turned around. That rule checks calls against the
    # functions they name; this one checks *definitions* against the shape
    # Remind will call them with.
    class CallbackSignature < Rule
      # name => arity Remind insists on.
      #
      # One argument: the prefix and suffix callbacks (given the priority) and
      # the two ordinal helpers. Three: the substitution-filter family, called
      # as `name(altmode, date, time)`.
      ONE_ARGUMENT = %w[msgprefix msgsuffix calprefix calsuffix ordx subst_ampm subst_ordinal].freeze

      THREE_ARGUMENTS = %w[
        subst_at subst_atx subst_bang subst_bangx subst_colon subst_colonx
        subst_hash subst_hashx subst_question subst_questionx
      ].freeze

      ARITIES = (
        ONE_ARGUMENT.to_h { |name| [name, 1] }
          .merge(THREE_ARGUMENTS.to_h { |name| [name, 3] })
      ).freeze

      # `get_function_override` builds `subst_<c>` and `subst_<c>x` for a
      # *single* alphanumeric or underscore character (src/dosubst.c). So
      # `subst_a` and `subst_ax` are callbacks and `subst_a_alt` is not -- it
      # is an ordinary helper, and Remind's own language packs are full of
      # them. Getting this wrong reports 45 offences against `include/lang`.
      OVERRIDE = /\Asubst_[a-z0-9_]x?\z/

      # A `%{name}` in the file makes `subst_name` a callback, called with the
      # same three arguments.
      NAMED = /%\{(?<name>[^}]*)\}/

      DEFINITION = /\A(?:-\s*)?(?<name>[A-Za-z_]\w*)\s*\((?<params>[^)]*)\)/

      def self.default_severity
        "warning"
      end

      def self.description
        "A Remind callback function defined with the wrong number of arguments."
      end

      def check
        @named = named_substitutions

        document.code_commands.each do |command|
          if command.keyword?("FSET")
            check_definition(command)
          end
        end
      end

      private

        def check_definition(command)
          match = command.args.match(DEFINITION)
          expected = match && arity_for(match[:name].downcase)

          if expected
            compare(command, match, expected)
          end
        end

        def arity_for(name)
          if ARITIES.key?(name)
            ARITIES.fetch(name)
          elsif name.match?(OVERRIDE) || @named.include?(name)
            3
          end
        end

        # `subst_` names this file actually asks Remind to call.
        def named_substitutions
          document.code_commands.flat_map do |command|
            command.text.scan(NAMED).flatten.map { |name| "subst_#{name.downcase}" }
          end
        end

        def compare(command, match, expected)
          actual = count(match[:params])

          if actual != expected
            offend(command.line, message(match[:name], expected, actual), column: command.keyword_column)
          end
        end

        def count(params)
          if params.strip.empty?
            0
          else
            params.split(",").length
          end
        end

        def message(name, expected, actual)
          "`#{name}` is a Remind callback and is called with #{expected} " \
          "argument#{expected == 1 ? '' : 's'}, not #{actual}; defined this way it is " \
          "never called at all, and nothing says so"
        end
    end
  end
end

__END__

require_relative "../document"

describe "RemLint::Rules::CallbackSignature" do
  lint = proc do |text|
    source = RemLint::Source.new(path: "t.rem", text: text)

    RemLint::Rules::CallbackSignature.new.run(RemLint::Document.new(source))
  end

  messages = proc { |text| lint.(text).map(&:message) }

  describe "the one-argument callbacks" do
    it "accepts the right shape" do
      lint.(%(FSET msgprefix(p) "[" + p + "] "\n)).should.be.empty
      lint.(%(FSET msgsuffix(p) char(8)\n)).should.be.empty
      lint.(%(FSET calprefix(p) ""\n)).should.be.empty
      lint.(%(FSET ordx(n) "th"\n)).should.be.empty
    end

    it "reports two arguments" do
      messages.(%(FSET msgprefix(p, q) ""\n)).first.should ==
        "`msgprefix` is a Remind callback and is called with 1 argument, not 2; " \
        "defined this way it is never called at all, and nothing says so"
    end

    it "reports none" do
      messages.(%(FSET msgprefix() ""\n)).length.should == 1
    end

    it "accepts subst_ampm and subst_ordinal, which take one" do
      lint.(%(FSET subst_ampm(x) "am"\n)).should.be.empty
      lint.(%(FSET subst_ordinal(x) "st"\n)).should.be.empty
    end
  end

  describe "the three-argument substitution family" do
    it "accepts the right shape" do
      lint.(%(FSET subst_at(a, d, t) "at"\n)).should.be.empty
      lint.(%(FSET subst_bangx(a, d, t) "is"\n)).should.be.empty
    end

    it "reports the wrong shape" do
      messages.(%(FSET subst_at(a, d) "at"\n)).first.should.match(
        /called with 3 arguments, not 2/,
      )
    end

    it "applies to the single-character overrides Remind builds" do
      messages.(%(FSET subst_a(x) "y"\n)).first.should.match(/called with 3 arguments, not 1/)
      messages.(%(FSET subst_ax(x) "y"\n)).first.should.match(/called with 3 arguments, not 1/)
      lint.(%(FSET subst_a(a, d, t) "y"\n)).should.be.empty
    end

    it "applies to a subst_ name the file reaches through %{name}" do
      text = %(FSET subst_myown(a) "x"\nREM 1 Jan MSG %{myown}\n)

      messages.(text).first.should.match(/called with 3 arguments, not 1/)
    end

    it "leaves an ordinary subst_ helper alone" do
      # include/lang/*.rem define dozens of these, and Remind never calls them
      # -- they are helpers the pack calls itself.
      lint.(%(FSET subst_a_alt(x) "y"\n)).should.be.empty
      lint.(%(FSET subst_hours(x) "y"\n)).should.be.empty
      lint.(%(FSET subst_tdiff(a, b) "y"\n)).should.be.empty
    end
  end

  describe "what it leaves alone" do
    it "says nothing about an ordinary function" do
      lint.("FSET double(x) x * 2\n").should.be.empty
      lint.("FSET greet(a, b, c, d) a\n").should.be.empty
    end

    it "matches the callback name case-insensitively" do
      messages.(%(FSET MsgPrefix(p, q) ""\n)).length.should == 1
    end

    it "accepts the FSET - form and still checks the shape" do
      lint.(%(FSET - msgprefix(p) ""\n)).should.be.empty
      messages.(%(FSET - msgprefix(p, q) ""\n)).length.should == 1
    end

    it "says nothing about comments" do
      lint.(%(# FSET msgprefix(p, q) ""\n)).should.be.empty
    end
  end

  it "points at the keyword" do
    lint.(%(   FSET msgprefix(p, q) ""\n)).first.column.should == 4
  end

  it "reports at warning severity" do
    lint.(%(FSET msgprefix(p, q) ""\n)).first.severity.should == "warning"
  end
end
