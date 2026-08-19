# frozen_string_literal: true

require_relative "lib/remlint/version"

Gem::Specification.new do |spec|
  spec.name        = "remlint"
  spec.version     = RemLint::VERSION
  spec.platform    = Gem::Platform::RUBY
  spec.license     = "GPL-2.0-only"
  spec.summary     = "A style and consistency linter for Remind reminder files"

  spec.description = <<~DESCRIPTION
    RemLint checks Remind reminder files for style, consistency and structure:
    unbalanced IF/ENDIF blocks, mistyped $SysVars, wrong argument counts,
    continuations that do not continue, and trailing whitespace that breaks
    rem2ps. Its vocabulary is transcribed from Remind's own dispatch tables, so
    keyword abbreviations and function arities match the interpreter exactly.

    It reads Remind out of shell heredocs as well as .rem files, and reports
    line numbers in the enclosing file.
  DESCRIPTION

  spec.author   = "Nathan Kidd"
  spec.email    = "nathanblenheimkidd@gmail.com"
  spec.homepage = "https://dianne.skoll.ca/projects/remind/"

  spec.required_ruby_version = ">= 3.3"

  spec.files = Dir[
    "lib/**/*.rb",
    "config/*.yml",
    "exe/*",
    "tasks/*.rb",
    "README.md",
  ]

  spec.bindir      = "exe"
  spec.executables = ["remlint"]
  spec.require_paths = ["lib"]
  spec.extra_rdoc_files = ["README.md"]

  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "rubocop", "~> 1.88"
  spec.add_development_dependency "scampi", "~> 1.0"
end
