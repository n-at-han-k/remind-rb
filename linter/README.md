# RemLint

A style and consistency linter for [Remind](https://dianne.skoll.ca/projects/remind/)
reminder files.

```
$ remlint examples tests
tests/if1.rem:3:1: error: [UnbalancedBlocks] `IF` is never closed by `ENDIF`
tests/test.rem:1146:9: error: [FunctionArity] `version` takes 0 arguments, given 1
tests/test.rem:592:6: error: [UnknownSystemVariable] `$aaaa…` is not a Remind system variable
3 offences (3 errors)
```

## Why it is shaped like this

**Remind is not Ruby, so RuboCop's machinery does not apply.** RuboCop's whole
pipeline assumes a `parser`/Prism AST, and its one escape hatch —
`RuboCop::Runner.ruby_extractors` — exists to pull *Ruby* back out of ERB and
Haml templates. Neither helps here.

The precedent that does apply is **puppet-lint**: a linter written in Ruby for a
language that is not Ruby. Including where puppet-lint draws its line — it
validates style, and leaves "is this even valid" to the real parser. RemLint
does the same. `Syntax` shells out to Remind itself, and is off by default,
because running the file is what checking it costs.

**Remind's grammar decides the architecture.** The manual describes a reminder
file as a list of commands, one per line, with backslash continuation; comments
open with `#` or `;`; keywords are case-insensitive and abbreviable; and the
`REM` that opens a trigger may be left off entirely. That is line-oriented, not
tree-oriented. So there is no grammar here — there is a pipeline:

```
bytes → sources → logical lines → commands → tokens → rules → offences
```

| Stage | File | What it settles |
| --- | --- | --- |
| sources | `extractors.rb` | which parts of a file are Remind, and at what line offset |
| logical lines | `logical_line.rb` | where backslash continuations join, and where they only look like they do |
| commands | `command.rb` | which keyword opens a line, and whether one does at all |
| tokens | `expr_lexer.rb` | where the strings, brackets, `$SysVars` and calls are |
| rules | `rules/*.rb` | one question each, over whichever view above is narrowest |

**The vocabulary is generated, not remembered.** Every keyword, its minimum
abbreviation length, every function's argument count, every system variable's
writability and range comes from Remind's own dispatch tables —
`src/token.c`, `src/funcs.c`, `src/var.c` — transcribed into `lib/remlint/tables.rb`
by `tasks/generate_tables.rb`. So `INC` resolves to `INCLUDE` and `OMI` resolves
to nothing for the same reason Remind says so, and `ampm` takes one to four
arguments because that is the row in Remind's table.

```
$ rake tables[/path/to/remind]
lib/remlint/tables.rb: 91 keywords, 145 functions, 126 system variables
```

**It reads Remind out of shell scripts.** `examples/ansitext` and
`examples/astro` are shell scripts that pipe Remind in through heredocs —
`astro` has four of them — and a linter that only globbed `*.rem` would miss
most of the Remind in that directory. Line numbers are reported against the
enclosing file, so an offence in `astro`'s third heredoc points at the real line
of `astro`.

## Rules

On by default — each reports something Remind itself rejects, or that breaks its
output:

| Rule | Reports |
| --- | --- |
| `TrailingWhitespace` | Whitespace at end of line. `remind.vim` flags this as an **Error**: "seem to break rem2ps". |
| `DanglingContinuation` | A backslash that does not continue the line, because whitespace follows it or the file ends. |
| `UnbalancedBlocks` | `IF`/`IFTRIG`/`ENDIF`, `ELSE`, and the `PUSH-`/`POP-` context stacks that do not pair up. |
| `UnbalancedDelimiters` | Brackets and parentheses that never close, or that cross. Remind's `Missing ']'` and `Missing ')'`. |
| `FunctionArity` | Calls with the wrong argument count, against Remind's table and the file's own `FSET`s. |
| `UnknownSystemVariable` | A `$Name` that is not in Remind's table. Its namespace is closed, so this is `E_NOSUCH_VAR`. |
| `SystemVariableAssignment` | `SET`/`UNSET` on a read-only variable, or a literal value outside its declared range. |
| `ColorComponentRange` | Colour components outside 0–255 in `SPECIAL COLOR`, `SPECIAL SHADE` and `ansicolor()`. |

Off by default — house style, plus the one rule that executes the file:

| Rule | Reports | Off because |
| --- | --- | --- |
| `KeywordCase` | Keywords in a case other than the file's own. | `examples/alignment.rem` deliberately mixes `MSG` and `msg`. |
| `LineLength` | Physical lines past `Max`. | A margin is a project's business. |
| `LicenseHeader` | No licence identifier near the top. | Project policy, not a Remind fact. |
| `Syntax` | Remind's own diagnostics. | It runs the file. `-r` disables `RUN`; `INCLUDECMD` still executes. |

`remlint --show-rules` lists them with their current state.

### Where the rules deliberately stay quiet

A linter earns its output by what it does *not* say. Three silences are load-bearing:

- **A closing bracket with nothing open is not an error.** `MSG See note ]`
  prints a bracket. Only unclosed openers and crossed pairs are reported.
- **Parentheses only count inside an expression.** `MSG Call (555) 1234` is
  text. Parentheses are tracked inside `[...]` and in the arguments of `IF`,
  `SET`, `FSET` and friends — nowhere else.
- **Unknown functions are not reported.** A file's helpers usually arrive
  through `INCLUDE`, which one-file linting cannot see.

## Configuration

`.remlint.yml`, found by walking up from the working directory, merged over the
shipped defaults **key by key** — so setting one option leaves the rest alone.

```yaml
TrailingWhitespace:
  Severity: error

KeywordCase:
  Enabled: true
  EnforcedStyle: consistent   # upper, lower, or the file's own majority

UnknownSystemVariable:
  AllowedNames: [Latitude, Longitude]   # fed in with remind -i$Name=...

Exclude:
  - "examples/tflag.rem"
```

`remlint --show-config` prints what is actually in effect.

### Silencing one line

```remind
MSG trailing spaces here    # remlint:disable TrailingWhitespace
```

```remind
# remlint:disable TrailingWhitespace, UnbalancedBlocks
IF something
```

A directive covers the line it is on and the line below it. `all` covers every
rule. Both comment characters work.

## Command line

```
remlint [options] [path...]

  -c, --config PATH      Configuration file (default: nearest .remlint.yml)
  -o, --only RULES       Run only these rules
  -f, --format TEMPLATE  Output template
      --fail-level LEVEL Exit non-zero at this severity or worse (default: warning)
      --show-rules       List the rules and whether they are on
      --show-config      Print the configuration in effect
```

With no paths, the working directory. Exit status is 0 when nothing at or above
`--fail-level` was found, 1 when something was, and 2 for a usage error.

The default output line — `path:line:column: severity: [Rule] message` — is what
vim's default `errorformat` reads. `--format` takes the same `%{...}`
placeholders puppet-lint uses:

```
$ remlint --format '::error file=%{path},line=%{line}::%{message}' .
```

## Development

Tests live in each file's `__END__` section and run under
[scampi](https://github.com/general-intelligence-systems/scampi): the specs
never load in production, because Ruby stops parsing at `__END__`.

```
$ bundle install
$ rake            # tests, then the house cops
$ rake test
$ rake rubocop
$ rake smoke[/path/to/remind]     # lint Remind's own corpus
```

The linter's own Ruby is checked by the custom cops in `cops/`, configured in
`.rubocop.yml`.

### The smoke test is the real test

RuboCop's advice for a new cop applies verbatim: run it over a significant
codebase. Remind ships one. On the current release, `remlint` is clean on
`examples/`, `include/` (584 files) and `contrib/`, and reports 25 offences in
`tests/` — every one of them a mistake that test suite makes on purpose:
`tests/if1.rem` opens an `IF` it never closes, `tests/test-pushpop2.rem` pops
three contexts that were never pushed, `tests/ansicolors.rem` passes `-1` and
`256` as colour components, and `tests/test.rem` calls `version(1)` and `max()`
under a heading that reads "Test error messages for function calls with too many
/ too few args".

Two of the rules exist in their current form *because* of that corpus:

- `FunctionArity` originally took the last `FSET` for a name file-wide.
  `tests/test.rem` defines `g(x, y)` on line 356 and redefines it as `g(x)` on
  line 1545, which made three correct calls in between look wrong. A call is now
  checked against the definition in force above it.
- `ColorComponentRange` originally picked out number tokens by position and so
  read `ansicolor(-1, 0, 0)` as an in-range `1`, because the lexer emits the
  minus sign as its own token. Arguments are now reassembled before being
  checked.

## Licence

GPL-2.0-only, as Remind is.
