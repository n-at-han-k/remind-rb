# frozen_string_literal: true

require_relative "expr_lexer"
require_relative "vocabulary"

module RemLint
  # The clauses of one command's trigger, and where its body starts.
  #
  # Everything before the reminder type -- `MSG`, `MSF`, `RUN`, `CAL`,
  # `SATISFY`, `SPECIAL`, `PS`, `PSFILE` -- is the trigger. Everything after is
  # the body, and the body is *text*.
  #
  # That boundary is the whole point of this class. `REM Tue AT 15:00 MSG Meet
  # Bob at the pub` contains the word `at` twice: once as the clause that sets
  # the time, once as an ordinary English preposition. A rule that grepped the
  # line for `AT` would find both. Scanning stops at the body keyword, so only
  # the first one is a clause.
  #
  # Hyphenated clause keywords (`MAX-OVERDUE`, `COMPLETE-THROUGH`) lex as three
  # tokens, so a name followed by a hyphen and another name is retried as one
  # word before being taken as two.
  class Trigger
    Clause = Struct.new(
      :keyword,
      :offset,
      :end_offset,
      :token_index,
      :token_width,
      keyword_init: true,
    ) do
      def name
        keyword.name
      end

      # Where the clause's argument starts, in tokens. A hyphenated keyword
      # such as `MAX-OVERDUE` occupies three of them, so this is not always
      # `token_index + 1`.
      def argument_index
        token_index + token_width
      end
    end

    # The commands that open a trigger. Everything else -- `ERRMSG`, `SET`,
    # `BANNER`, `INCLUDE` -- takes its own argument, and scanning that argument
    # for a reminder type finds words rather than keywords. Remind's own
    # `tests/tstlang.rem` has
    #
    #   errmsg Please run [filename()] with the -q and -r options
    #
    # where `run` is English. Treating it as the start of a RUN body makes the
    # rest of the sentence look like a shell command.
    TRIGGER_COMMANDS = %w[REM OMIT IFTRIG].freeze

    attr_reader :clauses, :body

    def initialize(tokens, triggered: true)
      @tokens = tokens
      @clauses = []
      @body = nil
      @triggered = triggered

      if triggered
        scan
      end
    end

    # Whether this command carries a trigger at all. Rules that look for
    # something positional -- a repeat, a delta -- need it, because `SET a 3*14`
    # has a `*` in it and no trigger for that `*` to be part of.
    def triggered?
      @triggered
    end

    def self.of(tokens, triggered: true)
      new(tokens, triggered: triggered)
    end

    # Whether this command carries a trigger at all: the three commands that
    # open one, a bare reminder type (`MSG hello`), or a trigger written with
    # the `REM` left off.
    def self.triggered?(command)
      command.implicit? ||
        command.keyword?(*TRIGGER_COMMANDS) ||
        !!command.keyword&.body?
    end

    # The clause of that name, or nil. Names are canonical, so `find("UNTIL")`
    # matches an abbreviated `UNTIL` written as `UNTI`.
    def find(name)
      clauses.find { |clause| clause.name == name.upcase }
    end

    def include?(*names)
      wanted = names.map(&:upcase)

      clauses.any? { |clause| wanted.include?(clause.name) }
    end

    def body?
      !body.nil?
    end

    # A body Remind runs the substitution filter over: everything but SATISFY.
    #
    # SATISFY's body is an *expression*, and in an expression `%` is the modulo
    # operator (`expr.c:1473`). `SATISFY [($Ty % 4) == 0]` in Remind's own
    # `examples/defs.rem` is arithmetic, not a malformed substitution, and a
    # rule that scanned it for `%` sequences would say so on every leap-year
    # test ever written.
    EXPRESSION_BODIES = %w[SATISFY].freeze

    def text_body?
      body? && !EXPRESSION_BODIES.include?(body.name)
    end

    # The tokens after the reminder type, which are the body's text. Empty for
    # a command with no body keyword at all.
    def body_tokens
      if body
        @tokens[(body.token_index + 1)..] || []
      else
        []
      end
    end

    # Where the body's text begins in the logical line, or nil.
    def body_offset
      body&.end_offset
    end

    private

      def scan
        index = 0

        while index < @tokens.length && body.nil?
          index += consume(index)
        end
      end

      # Returns how many tokens were taken, so a hyphenated keyword advances
      # past all three of its tokens rather than rediscovering its own tail.
      def consume(index)
        token = @tokens[index]

        if token.type != :name
          1
        else
          classify(index, token)
        end
      end

      def classify(index, token)
        joined = hyphenated(index)
        keyword = Vocabulary.keyword(joined || token.value)
        if joined
          width = 3
        else
          width = 1
        end

        if keyword.nil?
          1
        else
          record(
            keyword,
            token,
            index,
            width,
          )
          width
        end
      end

      # `MAX-OVERDUE` arrives as name, `-`, name. Only accepted when the joined
      # form actually resolves, so an ordinary `a-b` stays two names.
      def hyphenated(index)
        hyphen = @tokens[index + 1]
        tail = @tokens[index + 2]

        if hyphen&.type == :other && hyphen.value == "-" && tail&.type == :name
          candidate = "#{@tokens[index].value}-#{tail.value}"

          if Vocabulary.keyword(candidate)&.name&.include?("-")
            candidate
          end
        end
      end

      def record(keyword, token, index, width)
        last = @tokens[index + width - 1]

        clause = Clause.new(
          keyword:     keyword,
          offset:      token.offset,
          end_offset:  last.end_offset,
          token_index: index,
          token_width: width,
        )

        if keyword.body?
          @body = clause
        else
          @clauses << clause
        end
      end
  end
end

__END__

require_relative "document"

describe "RemLint::Trigger" do
  trigger = proc do |text|
    source = RemLint::Source.new(path: "t.rem", text: text)
    document = RemLint::Document.new(source)
    line = document.logical_lines.first

    RemLint::Trigger.of(document.tokens_for(line))
  end

  names = proc { |text| trigger.(text).clauses.map(&:name) }

  describe "finding clauses" do
    it "lists the clauses of a trigger, and not the reminder type" do
      # MSG ends the trigger, so it is the body rather than a clause.
      names.("REM Tuesday AT 15:00 MSG Staff Meeting").should == %w[REM TUESDAY AT]
    end

    it "answers include? by canonical name" do
      trigger.("REM 1 Jan UNTIL 2027-01-01 MSG hi").include?("UNTIL").should.be.true
      trigger.("REM 1 Jan MSG hi").include?("UNTIL").should.be.false
    end

    it "matches an abbreviated keyword" do
      trigger.("REM 1 Jan SCAN -7 MSG hi").include?("SCANFROM").should.be.true
    end

    it "is case-insensitive" do
      trigger.("rem tuesday at 15:00 msg hi").include?("AT").should.be.true
    end
  end

  describe "the trigger/body boundary" do
    it "stops scanning at the reminder type" do
      # The second `at` is English, not a clause.
      trigger.("REM Tue AT 15:00 MSG Meet Bob at the pub").clauses.count { |c|
        c.name == "AT"
      }.should == 1
    end

    it "does not find a clause keyword that only appears in the body" do
      trigger.("REM 1 Jan MSG Ask about the duration until Friday").include?("DURATION").should.be.false
      trigger.("REM 1 Jan MSG Ask about the duration until Friday").include?("UNTIL").should.be.false
    end

    it "records which reminder type ended the trigger" do
      trigger.("REM 1 Jan MSG hi").body.name.should == "MSG"
      trigger.("REM 1 Jan RUN echo hi").body.name.should == "RUN"
      trigger.("REM 1 Jan SATISFY [1]").body.name.should == "SATISFY"
    end

    it "reports no body for a command that has none" do
      trigger.("OMIT 1 January").should.not.be.body
      trigger.("OMIT 1 January").body_tokens.should.be.empty
    end

    it "gives the offset where the body's text starts" do
      command = "REM 1 Jan MSG hello"

      trigger.(command).body_offset.should == command.index("MSG") + 3
    end
  end

  describe "hyphenated clause keywords" do
    it "resolves them as one keyword" do
      trigger.("REM 1 Jan MAX-OVERDUE 5 MSG hi").include?("MAX-OVERDUE").should.be.true
    end

    it "reports the argument index past all three tokens" do
      found = trigger.("REM 1 Jan MAX-OVERDUE 5 MSG hi").find("MAX-OVERDUE")

      found.token_width.should == 3
      found.argument_index.should == found.token_index + 3
    end

    it "does not split one into its halves" do
      names.("REM 1 Jan MAX-OVERDUE 5 MSG hi").should.not.include "MAY"
    end

    it "leaves a hyphen alone when the joined form is not a keyword" do
      # MAY is a month; MAY-BE is nothing, so the hyphen must not swallow it.
      names.("REM MAY-BE 5 MSG hi").should == %w[REM MAY]
    end
  end

  describe "commands that carry no trigger" do
    triggered = proc do |text|
      source = RemLint::Source.new(path: "t.rem", text: text)
      document = RemLint::Document.new(source)

      RemLint::Trigger.triggered?(document.code_commands.first)
    end

    it "counts REM, OMIT and IFTRIG" do
      triggered.("REM 1 Jan MSG hi").should.be.true
      triggered.("OMIT 1 Jan MSG hi").should.be.true
      triggered.("IFTRIG 1 Jan").should.be.true
    end

    it "counts a bare reminder type and an implicit trigger" do
      triggered.("MSG hello").should.be.true
      triggered.("1 Nov ++12 MSG hi").should.be.true
    end

    it "does not count commands that take their own argument" do
      triggered.("ERRMSG Please run [filename()] with -q").should.be.false
      triggered.("SET a 1").should.be.false
      triggered.("BANNER %").should.be.false
      triggered.("INCLUDE defs.rem").should.be.false
    end

    it "finds nothing at all when told the command has no trigger" do
      source = RemLint::Source.new(path: "t.rem", text: "ERRMSG Please run [x] now")
      document = RemLint::Document.new(source)
      line = document.logical_lines.first
      bare = RemLint::Trigger.of(document.tokens_for(line), triggered: false)

      bare.body.should.be.nil
      bare.clauses.should.be.empty
    end
  end

  describe "text bodies versus expression bodies" do
    it "counts MSG, RUN and the rest as text" do
      trigger.("REM 1 Jan MSG hi").should.be.text_body
      trigger.("REM 1 Jan RUN cmd").should.be.text_body
      trigger.("REM 1 Jan CAL hi").should.be.text_body
    end

    it "does not count SATISFY, whose body is an expression" do
      # `%` there is modulo, not a substitution.
      trigger.("REM Tue Nov 2 SATISFY [($Ty % 4) == 0]").text_body?.should.be.false
    end

    it "does not count a command with no body at all" do
      trigger.("OMIT 1 January").text_body?.should.be.false
    end
  end

  it "handles a trigger written with no REM at all" do
    trigger.("1 Nov ++12 MSG Get ready").body.name.should == "MSG"
  end

  it "handles a comment without finding clauses in it" do
    trigger.("# until the AT clause").body.should.be.nil
  end
end
