# frozen_string_literal: true

require_relative "../rule"

module RemLint
  module Rules
    # `INCLUDE` and `SYSINCLUDE` paths that do not mean what they look like.
    #
    # TWO KEYWORDS, TWO BASE DIRECTORIES. `INCLUDE` resolves a relative path
    # against the *working directory*, not against the directory of the file
    # doing the including. The manual calls this a mistake kept for
    # compatibility, and `DO` is the keyword that resolves relative to the
    # file. So `INCLUDE defs.rem` works when you run Remind from the directory
    # the script lives in and fails from anywhere else -- from cron, most
    # memorably.
    #
    # `SYSINCLUDE` with an absolute path is the mirror image: for an absolute
    # path it is simply `INCLUDE`, so the keyword reads as though it pointed
    # into the system include directory when it does not.
    #
    # A path built from an expression -- `[$SysInclude]/ansitext.rem`, which is
    # how `examples/ansitext` does it -- is left alone, because what it
    # resolves to is not decidable here.
    class IncludePath < Rule
      ABSOLUTE = %r{\A/}

      def self.default_severity
        "warning"
      end

      def self.description
        "INCLUDE with a relative path, where DO resolves relative to the file, " \
        "or SYSINCLUDE with an absolute one."
      end

      def check
        document.code_commands.each do |command|
          path = literal_path(command)

          if path
            report(command, path)
          end
        end
      end

      private

        # The argument, when it is a plain path rather than something computed.
        def literal_path(command)
          if command.keyword?("INCLUDE", "SYSINCLUDE")
            text = command.args.strip

            unless text.empty? || text.include?("[") || text.include?("$")
              text
            end
          end
        end

        def report(command, path)
          if command.keyword?("INCLUDE") && !path.match?(ABSOLUTE)
            offend(command.line, relative_message(path), column: command.keyword_column)
          elsif command.keyword?("SYSINCLUDE") && path.match?(ABSOLUTE)
            offend(command.line, absolute_message(path), column: command.keyword_column)
          end
        end

        def relative_message(path)
          "`INCLUDE #{path}` resolves against the working directory, not this file's " \
          "directory; `DO #{path}` resolves relative to the file"
        end

        def absolute_message(path)
          "`SYSINCLUDE #{path}` is just `INCLUDE` for an absolute path, so the keyword " \
          "reads as though it pointed into the system include directory"
        end
    end
  end
end

__END__

require_relative "../document"

describe "RemLint::Rules::IncludePath" do
  lint = proc do |text|
    source = RemLint::Source.new(path: "t.rem", text: text)

    RemLint::Rules::IncludePath.new.run(RemLint::Document.new(source))
  end

  messages = proc { |text| lint.(text).map(&:message) }

  describe "INCLUDE" do
    it "reports a relative path" do
      messages.("INCLUDE defs.rem\n").first.should ==
        "`INCLUDE defs.rem` resolves against the working directory, not this file's " \
        "directory; `DO defs.rem` resolves relative to the file"
    end

    it "reports a path with a directory component" do
      messages.("INCLUDE holidays/us.rem\n").length.should == 1
    end

    it "reports a path that starts with a dot" do
      messages.("INCLUDE ./defs.rem\n").length.should == 1
    end

    it "accepts an absolute path" do
      lint.("INCLUDE /etc/remind/defs.rem\n").should.be.empty
    end

    it "accepts DO, which resolves relative to the file" do
      lint.("DO defs.rem\n").should.be.empty
    end

    it "matches the abbreviated keyword" do
      messages.("INC defs.rem\n").length.should == 1
    end
  end

  describe "SYSINCLUDE" do
    it "reports an absolute path" do
      messages.("SYSINCLUDE /etc/remind/defs.rem\n").first.should.match(
        /is just `INCLUDE` for an absolute path/,
      )
    end

    it "accepts a relative path, which is what it is for" do
      lint.("SYSINCLUDE ansitext.rem\n").should.be.empty
    end
  end

  describe "paths it cannot resolve" do
    it "says nothing about a bracketed expression" do
      # How examples/ansitext writes it.
      lint.("INCLUDE [$SysInclude]/ansitext.rem\n").should.be.empty
    end

    it "says nothing about a path built from a variable" do
      lint.("INCLUDE $SomeDir/defs.rem\n").should.be.empty
    end
  end

  it "says nothing about comments" do
    lint.("# INCLUDE defs.rem\n").should.be.empty
  end

  it "points at the keyword" do
    lint.("   INCLUDE defs.rem\n").first.column.should == 4
  end

  it "reports at warning severity" do
    lint.("INCLUDE defs.rem\n").first.severity.should == "warning"
  end
end
