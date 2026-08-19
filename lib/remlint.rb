# frozen_string_literal: true

require_relative "remlint/version"
require_relative "remlint/cli"
require_relative "remlint/config"
require_relative "remlint/document"
require_relative "remlint/extractors"
require_relative "remlint/formatter"
require_relative "remlint/rules"
require_relative "remlint/runner"

# A style and consistency linter for Remind reminder files.
#
# Remind is not Ruby, so none of RuboCop's machinery applies: there is no
# `parser` AST to walk, and its one escape hatch for non-Ruby input exists to
# pull Ruby back out of templates. The precedent that does apply is puppet-lint
# -- a linter written in Ruby for a language that is not Ruby -- including
# where it draws its line: it checks style and structure, and leaves "is this
# valid" to the real interpreter.
#
# Remind's grammar decides the architecture. The manual describes a file as a
# list of commands, one per line, with backslash continuation; comments open
# with `#` or `;`; keywords are case-insensitive and abbreviable; and the `REM`
# that opens a trigger may be left off entirely. That is line-oriented, not
# tree-oriented, so there is no grammar here -- there is a pipeline:
#
#   bytes -> sources -> logical lines -> commands -> tokens -> rules -> offences
#
# Each stage is in its own file and each is useful alone. What the vocabulary
# those stages match against is -- every keyword, its minimum abbreviation, every
# function's arity, every system variable's range -- is generated from Remind's
# own dispatch tables by `tasks/generate_tables.rb`, so it is transcription
# rather than recollection.
module RemLint
end
