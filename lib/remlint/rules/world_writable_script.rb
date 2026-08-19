# frozen_string_literal: true

require_relative "../rule"

module RemLint
  module Rules
    # A reminder file anyone can write to.
    #
    # Remind refuses a world-writable script outright, and disables `RUN` for
    # one it does not own -- because a reminder file is a program, and a
    # program anybody can edit will eventually run something somebody else
    # wrote. The check is in src/files.c (`CheckSafety`).
    #
    # This is the only rule that looks at a file rather than at its contents,
    # and the only one that can fail on a file that is textually perfect. It
    # earns its place because the failure mode is a cron job that stops
    # working, or worse does not, and the mode is invisible in every editor.
    #
    # Group-writable is reported separately and more quietly: Remind allows it,
    # but it means the file's safety rests on the group's membership.
    class WorldWritableScript < Rule
      WORLD_WRITABLE = 0o002
      GROUP_WRITABLE = 0o020

      def self.default_severity
        "error"
      end

      def self.description
        "A reminder file that is world-writable, which Remind refuses to read."
      end

      def check
        mode = mode_of(document.path)

        if mode
          report(mode)
        end
      end

      private

        # Only a real file on disk has a mode; text linted from a string has
        # nothing to check.
        def mode_of(path)
          if File.file?(path)
            File.stat(path).mode
          end
        rescue SystemCallError
          nil
        end

        def report(mode)
          if (mode & WORLD_WRITABLE).positive?
            offend(
              document.line_number_at(0),
              "this file is world-writable (mode #{format('%<mode>04o', mode: mode & 0o7777)}); " \
              "Remind refuses to read a script anyone can edit",
            )
          elsif (mode & GROUP_WRITABLE).positive?
            offend(
              document.line_number_at(0),
              "this file is group-writable (mode #{format('%<mode>04o', mode: mode & 0o7777)}); " \
              "Remind allows it, but the script's safety then rests on the group's membership",
            )
          end
        end
    end
  end
end

__END__

require "fileutils"
require "tmpdir"

require_relative "../document"

describe "RemLint::Rules::WorldWritableScript" do
  root = Dir.mktmpdir("remlint-modes")

  written = proc do |mode|
    path = File.join(root, "mode-#{format('%o', mode)}.rem")
    File.write(path, "MSG hi\n")
    File.chmod(mode, path)

    RemLint::Rules::WorldWritableScript.new.run(
      RemLint::Document.new(RemLint::Source.new(path: path, text: "MSG hi\n")),
    )
  end

  it "accepts a file only its owner can write" do
    written.(0o644).should.be.empty
    written.(0o600).should.be.empty
  end

  it "reports a world-writable file" do
    written.(0o666).first.message.should.match(
      /world-writable \(mode 0666\); Remind refuses to read a script anyone can edit/,
    )
  end

  it "reports a world-writable file whatever else it allows" do
    written.(0o777).length.should == 1
  end

  it "reports a group-writable file more quietly" do
    written.(0o664).first.message.should.match(/group-writable \(mode 0664\)/)
  end

  it "prefers the world-writable message when both apply" do
    written.(0o666).first.message.should.match(/world-writable/)
  end

  it "says nothing when there is no file on disk to stat" do
    source = RemLint::Source.new(path: "not-a-real-path.rem", text: "MSG hi\n")

    RemLint::Rules::WorldWritableScript.new.run(RemLint::Document.new(source)).should.be.empty
  end

  it "reports on the first line of the source" do
    written.(0o666).first.line.should == 1
  end

  it "reports at error severity" do
    written.(0o666).first.severity.should == "error"
  end
end
