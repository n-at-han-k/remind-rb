# frozen_string_literal: true

require_relative "lib/rem2ics/version"

Gem::Specification.new do |spec|
  spec.name        = "rem2ics"
  spec.version     = Rem2ics::VERSION
  spec.platform    = Gem::Platform::RUBY
  spec.license     = "GPL-2.0-only"
  spec.summary     = "Convert Remind reminder files to iCalendar (.ics)"

  spec.description = <<~DESCRIPTION
    Rem2ics turns the reminder files used by Remind into iCalendar, the format
    Outlook, Apple Calendar and Google Calendar import.

    It does not parse the reminder language. Remind does: rem2ics is built on
    the remind-rb bindings, so the trigger is parsed by ParseRem, the dates it
    fires on come from ComputeTrigger, and the message is rendered by DoSubst
    with its substitutions expanded. A recurring reminder becomes one event
    with an RRULE -- but only when the RRULE has been expanded and checked
    against the dates Remind gives; when the two disagree, as they do for a
    reminder that skips holidays, the event carries Remind's dates instead.
  DESCRIPTION

  spec.author   = "Nathan Kidd"
  spec.email    = "nathanblenheimkidd@gmail.com"
  spec.homepage = "https://dianne.skoll.ca/projects/remind/"

  spec.required_ruby_version = ">= 3.3"

  spec.files = Dir[
    "lib/rem2ics.rb",
    "lib/rem2ics/**/*.rb",
    "exe/rem2ics",
    "docs/rem2ics.md",
    "LICENSE",
  ]

  spec.bindir      = "exe"
  spec.executables = ["rem2ics"]
  spec.require_paths = ["lib"]
  spec.extra_rdoc_files = ["docs/rem2ics.md"]

  spec.add_dependency "icalendar", "~> 2.12"
  spec.add_dependency "ice_cube", "~> 0.17"
  spec.add_dependency "remind-rb", "~> 6.2"

  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "rubocop", "~> 1.88"
  spec.add_development_dependency "scampi", "~> 1.0"
end
