# frozen_string_literal: true

require_relative "lib/remind/version"

# Installing this gem never compiles anything.
#
# Remind is C, and building it means ./configure, make and a compiler. That is
# a packaging problem, and it is solved once, in CI: .github/workflows/native.yml
# builds the shared library on each platform and packages a gem with the
# library already inside. What `gem install remind-rb` does on any of those
# platforms is unpack it.
#
# `rake native` sets this to the platform being packaged. Nothing else should.
PRECOMPILED = ENV["REMIND_RB_PRECOMPILED"]

Gem::Specification.new do |spec|
  spec.name        = "remind-rb"
  spec.version     = Remind::VERSION
  spec.platform    = PRECOMPILED || Gem::Platform::RUBY
  spec.license     = "GPL-2.0-only"
  spec.summary     = "Ruby bindings for Remind, through Fiddle"

  spec.description = <<~DESCRIPTION
    Remind is a calendar program with a real expression language behind it: a
    Hebrew calendar, moon phases, sunrise and sunset, and date arithmetic that
    knows about weekdays, holidays and OMITted days. All of it is C, and all of
    it is reachable.

    remind-rb builds Remind's own sources into a shared library and binds them
    with Fiddle, so `moonphase(today())` and `sunrise('2027-06-21')` are Ruby
    calls rather than a shell-out and a parse of the output. Dates come back as
    Date objects, times as minutes, strings as strings.

    The Remind sources are vendored beside the gem, so the library binds the
    version it was built against rather than whatever is on the PATH.
  DESCRIPTION

  spec.author   = "Nathan Kidd"
  spec.email    = "nathanblenheimkidd@gmail.com"
  spec.homepage = "https://dianne.skoll.ca/projects/remind/"

  spec.required_ruby_version = ">= 3.3"

  # The vendored Remind release ships with the gem, because the gem builds its
  # shared library out of it: without the sources there is nothing to bind.
  # Only what `./configure` and the build actually read is included -- not the
  # book PDF, the Perl formatters or the Tcl front end.
  # Named by subtree, not by `lib/**/*.rb`: three gems share this lib/, the way
  # ratalada's three share theirs, and a glob would put the converter and the
  # linter inside the bindings.
  spec.files = Dir[
    "lib/remind.rb",
    "lib/remind/**/*.rb",
    "ext/remind/*.c",
    "README.md",
    "LICENSE",
    "remind-v*/src/*.[ch]",
    "remind-v*/src/*.in",
    # configure substitutes into these too, and stops if one is missing.
    "remind-v*/**/*.in",
    "remind-v*/include/**/*.rem",
    "remind-v*/docs/WHATSNEW",
    "remind-v*/configure",
    "remind-v*/configure.ac",
    "remind-v*/install-sh",
    "remind-v*/COPYRIGHT",
  ]

  # The precompiled gem carries the library instead of the sources it was
  # built from: with the .so in hand there is nothing left to configure. What
  # it keeps of the vendored release is the holiday files, which Remind reads
  # at runtime when a reminder INCLUDEs one.
  if PRECOMPILED
    spec.files -= Dir["remind-v*/src/**/*", "remind-v*/**/*.in", "remind-v*/configure*", "remind-v*/install-sh"]
    spec.files += Dir["lib/remind/libremind.{so,bundle,dll}"]
  end

  spec.require_paths = ["lib"]
  spec.extra_rdoc_files = ["README.md"]

  # Fiddle left the standard library in Ruby 3.5; naming it here is what keeps
  # the binding working on both sides of that move.
  spec.add_dependency "fiddle", "~> 1.1"

  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "rubocop", "~> 1.88"
  spec.add_development_dependency "scampi", "~> 1.0"
end
