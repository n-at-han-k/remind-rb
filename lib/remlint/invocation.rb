# frozen_string_literal: true

module RemLint
  # How a file is meant to be run, declared in the file.
  #
  # Three of the checks a Remind file wants need something that is not in the
  # file: the command line. `-g` decides whether a sort happens, `-p` versus
  # `-pp` decides whether `INFO` headers reach the back-end at all, and
  # calendar mode versus agenda mode decides whether `TODO` means anything.
  #
  # Rather than guess three times, the file says so once:
  #
  #     # remlint:invocation remind -pp -g /path/to/file
  #
  # No declaration means no opinion, and the rules that depend on it stay
  # silent. That is the honest default: a file with no declaration is one whose
  # invocation the linter genuinely does not know.
  class Invocation
    DIRECTIVE = /[#;]\s*remlint:invocation\s+(?<command>.+?)\s*\z/

    # `-p`, `-pp`, `-s`, `-c` and the `a`/`+`/digit suffixes each may carry.
    CALENDAR = /\A-(?<kind>[psc])(?<rest>[a-z+0-9]*)\z/

    SORT = /\A-g(?<spec>[a-z]*)\z/

    attr_reader :arguments

    def initialize(arguments)
      @arguments = arguments
    end

    # Reads the first declaration in a document, or an empty one.
    def self.of(document)
      declaration = document.raw_lines.filter_map { |raw| raw.match(DIRECTIVE) }.first

      new(declaration ? declaration[:command].split : [])
    end

    def declared?
      !arguments.empty?
    end

    # Any of the calendar-producing modes. Everything else is agenda mode,
    # which is where TODO semantics live.
    def calendar?
      arguments.any? { |argument| argument.match?(CALENDAR) }
    end

    def agenda?
      declared? && !calendar?
    end

    # `-pp` and above carry INFO headers to the back-end; plain `-p` does not.
    def carries_info?
      arguments.any? { |argument| argument.match?(/\A-p{2,}/) }
    end

    def simple_calendar?
      arguments.any? { |argument| argument.match?(/\A-p/) }
    end

    # The `-g` spec, or nil. Remind takes up to four characters, each `a` or
    # `d`, for date, time, priority and timedness.
    def sort_spec
      match = arguments.filter_map { |argument| argument.match(SORT) }.first

      match && match[:spec]
    end
  end
end

__END__

require_relative "document"

describe "RemLint::Invocation" do
  of = proc do |text|
    source = RemLint::Source.new(path: "t.rem", text: text)

    RemLint::Invocation.of(RemLint::Document.new(source))
  end

  it "is undeclared for a file that says nothing" do
    of.("MSG hi\n").should.not.be.declared
  end

  it "reads a declaration from a comment" do
    of.("# remlint:invocation remind -pp -g\nMSG hi\n").should.be.declared
  end

  it "reads one written with a semicolon" do
    of.("; remlint:invocation remind -pp\nMSG hi\n").should.be.declared
  end

  it "takes the first declaration when there are two" do
    invocation = of.("# remlint:invocation remind -p\n# remlint:invocation remind -c\nMSG hi\n")

    invocation.simple_calendar?.should.be.true
  end

  describe "calendar and agenda mode" do
    it "reads -c as a calendar" do
      of.("# remlint:invocation remind -c3 file\n").should.be.calendar
      of.("# remlint:invocation remind -c3 file\n").agenda?.should.be.false
    end

    it "reads -p and -s as calendars" do
      of.("# remlint:invocation remind -p file\n").should.be.calendar
      of.("# remlint:invocation remind -sa file\n").should.be.calendar
    end

    it "reads anything else as agenda mode" do
      of.("# remlint:invocation remind -q file\n").should.be.agenda
    end

    it "has no opinion when nothing is declared" do
      of.("MSG hi\n").agenda?.should.be.false
      of.("MSG hi\n").calendar?.should.be.false
    end
  end

  describe "INFO headers" do
    it "knows -pp carries them" do
      of.("# remlint:invocation remind -pp file\n").should.be.carries_info
    end

    it "knows plain -p does not" do
      of.("# remlint:invocation remind -p file\n").carries_info?.should.be.false
    end
  end

  describe "the sort spec" do
    it "reads the characters after -g" do
      of.("# remlint:invocation remind -gaad file\n").sort_spec.should == "aad"
    end

    it "reads a bare -g" do
      of.("# remlint:invocation remind -g file\n").sort_spec.should == ""
    end

    it "is nil when there is no -g" do
      of.("# remlint:invocation remind -q file\n").sort_spec.should.be.nil
    end
  end
end
