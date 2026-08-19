# frozen_string_literal: true

require "set"

require_relative "../rule"

module RemLint
  module Rules
    # `TZ` given a zone name the system does not have.
    #
    # Remind hands the name to the C library, which is case-sensitive: on a
    # system with a zone database, `america/toronto` is not `America/Toronto`.
    # An unrecognised name does not error -- the conversion simply produces
    # undefined results, which for a reminder means firing on the wrong day
    # some months from now.
    #
    # This is the one rule that reads something outside the file: the zone
    # database, at `TZDIR` or `/usr/share/zoneinfo`. Where there is no database
    # to read, it reports nothing rather than guessing -- a linter that cannot
    # run on a machine without tzdata is a linter that cannot run in CI.
    #
    # When a name matches a real zone except in case, the message names the
    # zone that was probably meant. That is the whole difference between a
    # rule that shrugs and one that can be acted on.
    class TimeZoneName < Rule
      DEFAULT_DIRECTORIES = ["/usr/share/zoneinfo", "/etc/zoneinfo"].freeze

      # `TZ ""` restores the local zone and is not a name to look up.
      LOCAL = ['""', "''"].freeze

      def self.default_severity
        "warning"
      end

      def self.description
        "A TZ name the zone database does not have, or one that differs only in case."
      end

      def check
        zones = database

        unless zones.fetch(:exact).empty?
          check_commands(zones)
        end
      end

      private

        def check_commands(zones)
          document.code_commands.each do |command|
            document.trigger_for(command).clauses.each do |clause|
              if clause.name == "TZ"
                check_clause(command, clause, zones)
              end
            end
          end
        end

        def check_clause(command, clause, zones)
          name = written_name(command, clause)

          if name && !zones.fetch(:exact).include?(name)
            report(
              command,
              clause,
              name,
              zones,
            )
          end
        end

        def written_name(command, clause)
          text = command.text[clause.end_offset..].to_s.strip[/\A\S+/]

          if text.nil? || LOCAL.include?(text) || text.include?("[")
            nil
          else
            text.delete('"').delete("'")
          end
        end

        def report(command, clause, name, zones)
          intended = zones.fetch(:folded)[name.downcase]

          offend_at(command.logical_line, clause.offset, message(name, intended))
        end

        def message(name, intended)
          if intended
            "`TZ #{name}` differs only in case from `#{intended}`; zone names are " \
            "case-sensitive, and an unrecognised one gives undefined results rather " \
            "than an error"
          else
            "`TZ #{name}` is not in the zone database; an unrecognised name gives " \
            "undefined results rather than an error"
          end
        end

        # Two indexes, not one. `exact` decides whether a name is real;
        # `folded` says what a wrong-case name was probably meant to be. Using
        # a single hash for both makes `america/toronto` look valid, which is
        # precisely the case this rule exists to catch.
        def database
          @database ||= build(option("Directory", nil))
        end

        def build(configured)
          root = configured || DEFAULT_DIRECTORIES.find { |path| Dir.exist?(path) }

          if root.nil?
            { exact: [], folded: {} }
          else
            index(root)
          end
        end

        def index(root)
          exact = []
          folded = {}

          Dir.glob("**/*", base: root).each do |entry|
            unless entry.include?(".") || !File.file?(File.join(root, entry))
              exact << entry
              folded[entry.downcase] ||= entry
            end
          end

          { exact: exact.to_set, folded: folded }
        end
    end
  end
end

__END__

require "fileutils"
require "tmpdir"

require_relative "../document"

describe "RemLint::Rules::TimeZoneName" do
  # A database of its own, so the specs do not depend on what the machine
  # running them happens to have installed.
  root = Dir.mktmpdir("remlint-zones")
  ["America/Toronto", "Europe/Amsterdam", "UTC"].each do |zone|
    path = File.join(root, zone)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, "")
  end

  lint = proc do |text|
    source = RemLint::Source.new(path: "t.rem", text: text)

    RemLint::Rules::TimeZoneName.new("Directory" => root).run(RemLint::Document.new(source))
  end

  messages = proc { |text| lint.(text).map(&:message) }

  it "accepts a zone the database has" do
    lint.("REM Fri AT 23:30 TZ America/Toronto MSG hi\n").should.be.empty
    lint.("REM Fri AT 23:30 TZ UTC MSG hi\n").should.be.empty
  end

  it "accepts a quoted zone name" do
    lint.(%(REM Fri AT 23:30 TZ "America/Toronto" MSG hi\n)).should.be.empty
  end

  it "accepts the empty TZ that restores the local zone" do
    lint.(%(REM Fri AT 23:30 TZ "" MSG hi\n)).should.be.empty
  end

  it "reports a zone the database does not have" do
    messages.("REM Fri AT 23:30 TZ Mars/Olympus MSG hi\n").first.should ==
      "`TZ Mars/Olympus` is not in the zone database; an unrecognised name gives " \
      "undefined results rather than an error"
  end

  it "names the zone that was probably meant when only the case differs" do
    messages.("REM Fri AT 23:30 TZ america/toronto MSG hi\n").first.should.match(
      /differs only in case from `America\/Toronto`/,
    )
  end

  it "says nothing about a computed zone" do
    lint.("REM Fri AT 23:30 TZ [zone()] MSG hi\n").should.be.empty
  end

  it "says nothing about a reminder with no TZ" do
    lint.("REM Fri AT 23:30 MSG hi\n").should.be.empty
  end

  it "says nothing about comments" do
    lint.("# REM Fri AT 23:30 TZ Mars/Olympus MSG hi\n").should.be.empty
  end

  it "reports nothing at all when there is no database to read" do
    source = RemLint::Source.new(path: "t.rem", text: "REM Fri AT 1:00 TZ Nope MSG hi\n")
    rule = RemLint::Rules::TimeZoneName.new("Directory" => "/nonexistent/zoneinfo")

    rule.run(RemLint::Document.new(source)).should.be.empty
  end

  it "points at the clause" do
    text = "REM Fri AT 23:30 TZ Mars/Olympus MSG hi\n"

    lint.(text).first.column.should == text.index("TZ ") + 1
  end

  it "reports at warning severity" do
    lint.("REM Fri AT 23:30 TZ Mars/Olympus MSG hi\n").first.severity.should == "warning"
  end
end
