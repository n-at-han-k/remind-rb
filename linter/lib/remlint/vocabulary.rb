# frozen_string_literal: true

require_relative "tables"

module RemLint
  # Lookups over the generated tables, reproducing Remind's own resolution
  # rules rather than approximating them.
  #
  # The three rules differ from each other, and each difference is a bug class
  # if you get it wrong:
  #
  #   keywords   case-insensitive, abbreviable to a per-keyword minimum length
  #              (src/token.c FindToken)
  #   functions  case-insensitive, exact -- no abbreviation
  #              (src/funcs.c FindBuiltinFunc)
  #   $SysVars   case-insensitive, exact -- no abbreviation
  #              (src/var.c FindSysVar)
  module Vocabulary
    # The clause keywords -- UNTIL, AT, WARN and so on -- appear inside a
    # trigger rather than at the head of a line, so a rule looking at the first
    # word of a command needs to tell the two apart.
    CLAUSE_TYPES = %w[
      T_Month T_WkDay T_Ordinal T_Skip T_At T_Duration T_Until T_Warn
      T_Sched T_Scanfrom T_Through T_Once T_Priority T_Tag T_In T_Tz
      T_BackAdj T_Info T_NoQueue T_MaxOverdue T_CompleteThrough
      T_MaybeUncomputable T_OmitFunc
    ].freeze

    Keyword = Struct.new(:name, :minlen, :type) do
      def clause?
        CLAUSE_TYPES.include?(type)
      end

      # `MSG`, `MSF`, `RUN`, `CAL`, `SATISFY`, `SPECIAL`, `PS`, `PSFILE` --
      # the token that ends a trigger and starts the reminder body.
      def body?
        type == "T_RemType"
      end
    end

    Function = Struct.new(:name, :min, :max) do
      def variadic?
        max == Tables::NO_MAX_ARGS
      end

      def accepts?(count)
        count >= min && (variadic? || count <= max)
      end

      # "1", "2 to 5", "at least 2" -- the phrasing an arity message needs.
      def arity_description
        if variadic?
          "at least #{min}"
        elsif min == max
          min.to_s
        else
          "#{min} to #{max}"
        end
      end
    end

    SysVar = Struct.new(
      :name,
      :modifiable,
      :type,
      :min,
      :max,
    ) do
      def bounded?
        !min.nil? && !max.nil?
      end

      def in_range?(value)
        value >= min && value <= max
      end
    end

    KEYWORDS = Tables::KEYWORD_ROWS.map { |row| Keyword.new(*row).freeze }.freeze

    FUNCTIONS = Tables::FUNCTION_ROWS.to_h do |row|
      function = Function.new(*row).freeze

      [function.name, function]
    end.freeze

    SYSVARS = Tables::SYSVAR_ROWS.to_h do |row|
      sysvar = SysVar.new(*row).freeze

      [sysvar.name.downcase, sysvar]
    end.freeze

    # Resolved lookups, because the linter asks the same questions about the
    # same words over and over: every `:name` token in every trigger goes
    # through `keyword`, and a linear walk of 91 entries per token is the
    # difference between 3.3 and 1.9 seconds per megabyte. Bounded by the
    # distinct words in the files being linted.
    #
    # Guarded like Rule::REGISTRY: `scampi` re-executes each file's top level
    # to reach its specs, and an unguarded literal would drop the cache
    # mid-run.
    unless defined?(KEYWORD_CACHE)
      KEYWORD_CACHE = {}
    end

    module_function

    # Resolve one whitespace-delimited word the way FindToken does: the first
    # entry in table order whose name the word prefixes, provided the word is
    # at least that entry's minimum abbreviation length. A trailing comma is
    # ignored, as Remind's TokStrCmp ignores it.
    def keyword(word)
      needle = word.to_s.downcase.delete_suffix(",")

      if needle.empty?
        nil
      else
        KEYWORD_CACHE.fetch(needle) { KEYWORD_CACHE[needle] = resolve(needle) }
      end
    end

    def resolve(needle)
      KEYWORDS.find do |candidate|
        needle.length >= candidate.minlen && candidate.name.downcase.start_with?(needle)
      end
    end

    def function(name)
      FUNCTIONS[name.to_s.downcase]
    end

    def sysvar(name)
      SYSVARS[name.to_s.delete_prefix("$").downcase]
    end
  end
end

__END__

describe "RemLint::Vocabulary.keyword" do
  it "resolves a full keyword regardless of case" do
    RemLint::Vocabulary.keyword("MSG").name.should == "MSG"
    RemLint::Vocabulary.keyword("msg").name.should == "MSG"
    RemLint::Vocabulary.keyword("MsG").name.should == "MSG"
  end

  it "accepts an abbreviation at or past the minimum length" do
    # `include` has MinLen 3, which is what makes INC an INCLUDE.
    RemLint::Vocabulary.keyword("inc").name.should == "INCLUDE"
    RemLint::Vocabulary.keyword("inclu").name.should == "INCLUDE"
  end

  it "rejects an abbreviation shorter than the minimum length" do
    # `omit` has MinLen 4, so `omi` is not a keyword at all.
    RemLint::Vocabulary.keyword("omi").should.be.nil
  end

  it "resolves the hyphenated context keywords" do
    RemLint::Vocabulary.keyword("PUSH-OMIT-CONTEXT").name.should == "PUSH-OMIT-CONTEXT"
    RemLint::Vocabulary.keyword("PUSH").name.should == "PUSH-OMIT-CONTEXT"
    RemLint::Vocabulary.keyword("POP").name.should == "POP-OMIT-CONTEXT"
  end

  it "ignores a trailing comma, as TokStrCmp does" do
    RemLint::Vocabulary.keyword("mon,").name.should == "MONDAY"
  end

  it "caches a resolved word without changing the answer" do
    RemLint::Vocabulary.keyword("msg").name.should == "MSG"
    RemLint::Vocabulary.keyword("msg").name.should == "MSG"
    RemLint::Vocabulary.keyword("frobnicate").should.be.nil
    RemLint::Vocabulary.keyword("frobnicate").should.be.nil
  end

  it "returns nil for a word that is not a keyword" do
    RemLint::Vocabulary.keyword("frobnicate").should.be.nil
    RemLint::Vocabulary.keyword("").should.be.nil
  end

  it "distinguishes clause keywords from body keywords" do
    RemLint::Vocabulary.keyword("UNTIL").should.be.clause
    RemLint::Vocabulary.keyword("MSG").should.be.body
    RemLint::Vocabulary.keyword("MSG").clause?.should.be.false
  end
end

describe "RemLint::Vocabulary.function" do
  it "looks up builtins case-insensitively and exactly" do
    RemLint::Vocabulary.function("trigger").name.should == "trigger"
    RemLint::Vocabulary.function("TRIGGER").name.should == "trigger"
    RemLint::Vocabulary.function("trigg").should.be.nil
  end

  it "reports arity from Remind's own table" do
    RemLint::Vocabulary.function("abs").accepts?(1).should.be.true
    RemLint::Vocabulary.function("abs").accepts?(2).should.be.false
    RemLint::Vocabulary.function("abs").arity_description.should == "1"
  end

  it "reports a range for optional arguments" do
    ampm = RemLint::Vocabulary.function("ampm")
    ampm.accepts?(1).should.be.true
    ampm.accepts?(4).should.be.true
    ampm.accepts?(5).should.be.false
    ampm.arity_description.should == "1 to 4"
  end

  it "treats NO_MAX_ARGS as variadic" do
    char = RemLint::Vocabulary.function("char")
    char.should.be.variadic
    char.accepts?(99).should.be.true
    char.accepts?(0).should.be.false
    char.arity_description.should == "at least 1"
  end
end

describe "RemLint::Vocabulary.sysvar" do
  it "looks up system variables case-insensitively, with or without the sigil" do
    RemLint::Vocabulary.sysvar("$FormWidth").name.should == "FormWidth"
    RemLint::Vocabulary.sysvar("formwidth").name.should == "FormWidth"
    RemLint::Vocabulary.sysvar("$NoSuchVariable").should.be.nil
  end

  it "knows which variables reject SET" do
    RemLint::Vocabulary.sysvar("$CalMode").modifiable.should.be.false
    RemLint::Vocabulary.sysvar("$FormWidth").modifiable.should.be.true
  end

  it "carries the range only for the integer variables Remind bounds" do
    form_width = RemLint::Vocabulary.sysvar("$FormWidth")
    form_width.should.be.bounded
    form_width.in_range?(20).should.be.true
    form_width.in_range?(19).should.be.false

    RemLint::Vocabulary.sysvar("$Ago").bounded?.should.be.false
  end
end
