#!/usr/bin/env ruby
# frozen_string_literal: true

# Regenerates lib/remlint/tables.rb from the Remind C sources.
#
# Every fact the linter asserts about Remind's vocabulary -- which keywords
# exist, how far each may be abbreviated, which functions take how many
# arguments, which system variables are writable and over what range -- is
# transcribed from the tables Remind itself dispatches on:
#
#   src/token.c  TokArray[]    keyword, minimum abbreviation length, type
#   src/funcs.c  Func[]        builtin name, min args, max args
#   src/var.c    SysVarArr[]   $SysVar name, modifiable flag, type, min, max
#
# Hand-maintaining that vocabulary would guarantee drift the first time Remind
# gains a function. Run this against a Remind checkout instead:
#
#   ruby tasks/generate_tables.rb /path/to/remind
#
# The generated file is committed, so the gem builds and tests without a
# Remind checkout present.

require "pathname"

SOURCE_ROOT = Pathname.new(ARGV.fetch(0, "..")).expand_path
OUTPUT      = Pathname.new(__dir__).join("../lib/remlint/tables.rb").cleanpath

# `{ "banner", 3, T_Banner, 0 },` -- name, minimum abbreviation length, type.
TOKEN_ROW = /^\s*\{\s*"([a-z0-9-]+)"\s*,\s*(\d+)\s*,\s*(T_\w+)\s*,/

# `{ "ampm", 1, 4, 1, FAmpm, NULL },` -- name, min args, max args.
# NO_MAX_ARGS (127) is Remind's "variadic" sentinel.
FUNC_ROW = /^\s*\{\s*"([a-z0-9_]+)"\s*,\s*(\d+|NO_MAX_ARGS)\s*,\s*(\d+|NO_MAX_ARGS)\s*,/

# `{"FormWidth", 1, INT_TYPE, &FormWidth, 20, 500 },`
# -- name, modifiable, type, value, min, max. The min/max columns only bound
# anything for INT_TYPE; for the other types they are 0/0 filler.
SYSVAR_ROW = /^\s*\{\s*"(\w+)"\s*,\s*([01])\s*,\s*(\w+)\s*,\s*[^,]+,\s*([^,]+),\s*([^}]+)\}/

NO_MAX_ARGS = 127

def read_source(relative)
  path = SOURCE_ROOT.join(relative)

  unless path.exist?
    abort "#{path} not found; pass the root of a Remind checkout as ARGV[0]"
  end

  path.read
end

def scan(relative, pattern)
  read_source(relative).each_line.filter_map do |line|
    match = line.match(pattern)

    if match
      yield match
    end
  end
end

def parse_arg_count(text)
  if text == "NO_MAX_ARGS"
    NO_MAX_ARGS
  else
    Integer(text)
  end
end

# Only INT_TYPE variables carry a real range, and only when the two columns
# actually differ -- `0, 0` is Remind's filler, not a variable pinned to zero.
def parse_bounds(type, min, max)
  if type == "INT_TYPE" && min.strip.match?(/\A-?\d+\z/) && max.strip.match?(/\A-?\d+\z/) && min.strip != max.strip
    [Integer(min.strip), Integer(max.strip)]
  else
    [nil, nil]
  end
end

def literal(value)
  case value
  when nil    then "nil"
  when String then value.inspect
  else value.to_s
  end
end

def render_rows(rows, columns)
  widths = columns.to_h do |column|
    [column, rows.map { |row| literal(row[column]).length }.max]
  end

  rows.map do |row|
    cells = columns.map do |column|
      literal(row[column]).ljust(widths.fetch(column))
    end

    "      [#{cells.join(', ')}],"
  end
end

keywords = scan("src/token.c", TOKEN_ROW) do |match|
  {
    name:   match[1].upcase,
    minlen: Integer(match[2]),
    type:   match[3],
  }
end

functions = scan("src/funcs.c", FUNC_ROW) do |match|
  {
    name: match[1],
    min:  parse_arg_count(match[2]),
    max:  parse_arg_count(match[3]),
  }
end

sysvars = scan("src/var.c", SYSVAR_ROW) do |match|
  min, max = parse_bounds(match[3], match[4], match[5])

  {
    name:       match[1],
    modifiable: match[2] == "1",
    type:       match[3],
    min:        min,
    max:        max,
  }
end

# src/version.h.in holds an unsubstituted @VERSION@ placeholder in a source
# tree that has not been configured, so take the number from its origin.
version = read_source("configure.ac")[/AC_INIT\(\s*remind\s*,\s*([^,\s)]+)/, 1] || "unknown"

body = <<~GENERATED
  # frozen_string_literal: true

  # GENERATED FILE -- do not edit by hand.
  #
  # Transcribed from Remind #{version} by tasks/generate_tables.rb, which reads
  # the same tables the interpreter dispatches on (src/token.c, src/funcs.c,
  # src/var.c). Regenerate rather than patch:
  #
  #   ruby tasks/generate_tables.rb /path/to/remind
  module RemLint
    # Remind's vocabulary, exactly as the interpreter knows it.
    module Tables
      # Remind's variadic sentinel: `char(...)` and friends take any number of
      # arguments above their minimum.
      NO_MAX_ARGS = #{NO_MAX_ARGS}

      # [keyword, minimum abbreviation length, token type]. Remind accepts any
      # prefix at least `minlen` characters long, which is why `INC` is
      # `INCLUDE` and `SCAN` is `SCANFROM`.
      KEYWORD_ROWS = [
  #{render_rows(keywords, %i[name minlen type]).join("\n")}
      ].freeze

      # [name, minimum arguments, maximum arguments].
      FUNCTION_ROWS = [
  #{render_rows(functions, %i[name min max]).join("\n")}
      ].freeze

      # [name, modifiable, type, minimum, maximum]. Non-modifiable variables
      # are readable but reject `SET`; the bounds are populated only for the
      # integer-valued variables Remind range-checks.
      SYSVAR_ROWS = [
  #{render_rows(sysvars, %i[name modifiable type min max]).join("\n")}
      ].freeze
    end
  end
GENERATED

OUTPUT.write(body)

puts "#{OUTPUT}: #{keywords.size} keywords, #{functions.size} functions, #{sysvars.size} system variables"
