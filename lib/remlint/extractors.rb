# frozen_string_literal: true

require_relative "source"

module RemLint
  # Turns a file on disk into zero or more {Source} runs of Remind code.
  #
  # A linter that only globs `*.rem` misses most real Remind code: the shipped
  # `examples/ansitext` and `examples/astro` are shell scripts that pipe Remind
  # in through heredocs, and `astro` alone holds four of them. Linting such a
  # file as if it were Remind produces nothing but noise about the shell.
  #
  # So extraction is its own layer, mirroring how RuboCop pulls Ruby out of ERB
  # and Haml: each extractor either recognises the file and returns its Remind
  # runs, or returns nil and lets the next one look.
  module Extractors
    # `remind ... <<'EOF'` / `<<-EOF` / `<< "EOF"`, with the flags and
    # redirections in between ignored. The quoting around the delimiter is what
    # stops the shell interpolating `$Latitude` before Remind sees it; both
    # quoted and bare forms open a heredoc, so both are matched.
    HEREDOC_OPENER = /\bremind\b[^\n<]*<<(?<dash>-?)\s*(?<quote>['"]?)(?<delimiter>\w+)\k<quote>/

    # A file Remind is meant to read directly, either by extension or because
    # it runs itself through Remind.
    REM_SHEBANG = /\A#![^\n]*\bremind\b/

    module_function

    # A plain Remind file: the whole text, no offset.
    def rem_file(path, text)
      if File.extname(path).casecmp?(".rem") || text.match?(REM_SHEBANG)
        [Source.new(path: path, text: text)]
      end
    end

    # Remind embedded in shell heredocs. Returns nil rather than an empty array
    # when the file holds none, so the extractor chain keeps looking.
    def shell_heredoc(path, text)
      sources = scan_heredocs(path, text)

      unless sources.empty?
        sources
      end
    end

    # Ordered most-specific-first: a `.rem` file is taken whole, and only a file
    # that is not itself Remind gets searched for embedded heredocs.
    ALL = [method(:rem_file), method(:shell_heredoc)].freeze

    # The first extractor that recognises the file wins.
    def extract(path, text)
      ALL.lazy.filter_map { |extractor| extractor.call(path, text) }.first || []
    end

    def scan_heredocs(path, text)
      lines = text.lines
      sources = []
      index = 0

      while index < lines.length
        match = lines[index].match(HEREDOC_OPENER)

        if match
          body_start = index + 1
          body_end = find_terminator(
            lines,
            body_start,
            match[:delimiter],
            match[:dash] == "-",
          )

          sources << Source.new(
            path:        path,
            text:        lines[body_start...body_end].join,
            line_offset: body_start,
            description: "heredoc at line #{index + 1}",
          )

          index = body_end
        end

        index += 1
      end

      sources
    end

    # `<<-` lets the closing delimiter be indented; plain `<<` demands it sit
    # at column zero. An unterminated heredoc runs to end of file, which is
    # what the shell would do too.
    def find_terminator(lines, from, delimiter, allow_indent)
      cursor = from

      while cursor < lines.length && !terminator?(lines[cursor], delimiter, allow_indent)
        cursor += 1
      end

      cursor
    end

    def terminator?(line, delimiter, allow_indent)
      body = line.chomp

      if allow_indent
        body.sub(/\A\t+/, "") == delimiter
      else
        body == delimiter
      end
    end
  end
end

__END__

describe "RemLint::Extractors" do
  extract = proc { |path, text| RemLint::Extractors.extract(path, text) }

  describe "plain Remind files" do
    it "takes a .rem file whole, with no offset" do
      sources = extract.("holidays.rem", "REM 1 Jan MSG New Year\n")

      sources.length.should == 1
      sources.first.text.should == "REM 1 Jan MSG New Year\n"
      sources.first.line_offset.should == 0
    end

    it "recognises the extension regardless of case" do
      extract.("Holidays.REM", "MSG hi\n").length.should == 1
    end

    it "recognises a Remind shebang on a file with no extension" do
      sources = extract.("alignment", "#!/usr/bin/env -S remind -@2\nMSG hi\n")

      sources.length.should == 1
      sources.first.line_offset.should == 0
    end
  end

  describe "shell heredocs" do
    script = <<~SHELL
      #!/bin/sh
      # a comment
      remind -@2 - <<'EOF'
      BANNER %
      MSG hello
      EOF
      exit 0
    SHELL

    it "extracts the heredoc body and nothing else" do
      sources = extract.("ansitext", script)

      sources.length.should == 1
      sources.first.text.should == "BANNER %\nMSG hello\n"
    end

    it "offsets by the number of lines before the body" do
      # The body starts on physical line 4, so the offset is the 3 lines above.
      extract.("ansitext", script).first.line_offset.should == 3
    end

    it "finds every heredoc in a file that has several" do
      four = <<~SHELL
        #!/bin/sh
        remind -q -@2 - "$@" <<'EOF'
        MSG one
        EOF
        echo between
        remind -q -@2 - "$@" <<'EOF'
        MSG two
        EOF
      SHELL

      sources = extract.("astro", four)
      sources.length.should == 2
      sources.map(&:text).should == ["MSG one\n", "MSG two\n"]
      sources.map(&:line_offset).should == [2, 6]
    end

    it "handles an unquoted delimiter" do
      extract.("s", "#!/bin/sh\nremind - <<EOF\nMSG hi\nEOF\n").first.text.should == "MSG hi\n"
    end

    it "allows an indented terminator only for the <<- form" do
      dash = "#!/bin/sh\nremind - <<-EOF\n\tMSG hi\n\tEOF\nafter\n"
      extract.("s", dash).first.text.should == "\tMSG hi\n"

      plain = "#!/bin/sh\nremind - <<EOF\nMSG hi\n\tEOF\n"
      extract.("s", plain).first.text.should == "MSG hi\n\tEOF\n"
    end

    it "runs an unterminated heredoc to end of file" do
      extract.("s", "#!/bin/sh\nremind - <<'EOF'\nMSG hi\n").first.text.should == "MSG hi\n"
    end

    it "describes which heredoc a source came from" do
      extract.("astro", script).first.label.should == "astro (heredoc at line 3)"
    end
  end

  describe "files that are not Remind at all" do
    it "yields nothing" do
      extract.("build.sh", "#!/bin/sh\necho hello\n").should.be.empty
    end

    it "does not mistake a mention of remind in a comment for a heredoc" do
      extract.("notes.txt", "# see remind for details\n").should.be.empty
    end
  end
end
