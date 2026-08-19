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

53 rules. `remlint --show-rules` lists them with their current state; each
carries its reasoning, and the file and line of the C that settles it, in a
comment at the top of `lib/remlint/rules/`.

**On by default** — each reports something Remind itself rejects, that breaks
its output, or that fails silently on a day months away:

`TrailingWhitespace` · `DanglingContinuation` · `UnbalancedBlocks` ·
`UnbalancedDelimiters` · `FunctionArity` · `UnknownSystemVariable` ·
`SystemVariableAssignment` · `ColorComponentRange` · `UnquotedShellSubstitution` ·
`ClauseRequiresAt` · `IftrigWithSatisfy` · `UnknownSubstitutionSequence` ·
`InfoSubstitutionWithoutHeader` · `TextAfterEofMarker` · `UntilBeforeFrom` ·
`CoordinateNotString` · `ShellUseWhileRunDisabled` · `LiteralTypeMismatch` ·
`ClauseValueRange` · `DateOutOfRange` · `ClauseNeedsFullDate` · `RepeatTrigger` ·
`InfoClause` · `TagSyntax` · `BannerPlacement` · `UnknownSpecialType` ·
`StringEscape` · `DebugCommand` · `ShellMaxlen` · `FunctionRedefinition` ·
`PushVarsMissingName` · `CallbackSignature` · `IncludePath` ·
`EasterdateFromToday` · `TimeZoneName` · `WorldWritableScript` ·
`TodoCompleteThrough` · `AddomitWithoutScanfrom` · `TranslateCommand` ·
`HebrewDate` · `MoonPhaseArgument` · `TkTagNamespace` · `InvocationMismatch` ·
`LocalizationPack` · `GeneratedFileEdited`

**Off by default** — house style, one performance rule, and the one that runs
the file:

`KeywordCase` · `LineLength` · `LicenseHeader` · `SatisfyConstraint` ·
`AdvanceWarningBody` · `CalendarTextLimited` · `OmitAwareDelta` · `Syntax`

`Syntax` is off deliberately: Remind has no parse-only mode, so it runs the
file. `-r` disables `RUN`; `INCLUDECMD` still executes.

### Where the rules deliberately stay quiet

A linter earns its output by what it does *not* say. The recurring principle:
**where the linter cannot know, it says nothing.**

- A closing bracket with nothing open is text, not an error — `MSG See note ]`
  prints a bracket.
- Parentheses count only inside `[...]` or an expression command; `MSG Call
  (555) 1234` is text.
- Unknown functions are not reported: a file's helpers usually arrive through
  `INCLUDE`, which one-file linting cannot see.
- A trigger carrying a bracketed expression suppresses the clause rules that
  depend on knowing what it evaluates to.

### Declaring how a file is run

Three checks need the command line rather than the file. Declare it once and
they work; leave it out and they stay silent.

```remind
# remlint:invocation remind -pp -g /path/to/file
```

`InvocationMismatch` then reports an unreadable `-g` sort spec, `INFO` under a
plain `-p` that will not carry it, and `TODO` under a calendar invocation where
its semantics do not exist.

`RULES.md` records the full backlog: every one of the 100 ideas built, merged or
deleted with its reason, and the thirteen book premises the source and corpus
corrected.

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

### The corpus is the real test

RuboCop's advice for a new cop applies verbatim: run it over a significant
codebase. Remind ships one, and it earned its keep — **fifteen** premises are
narrower than they started, or gone entirely, because the source, the man page
or a running binary said so; two of the linter's own bugs surfaced the same way;
and three rules were built, run, disproven and deleted.

On the current release `remlint` is clean on `examples/`, `include/` (584 files)
and `contrib/`, and reports 84 offences in `tests/` — all verified by hand, many
on lines that suite labels "Should fail", "Bad:" or "Diagnosed".

A few of the corrections, as a flavour of what a corpus is for:

- **A trailing `%` is documented**, not a stray. It suppresses the newline
  Remind would otherwise append: `dosubst("hello")` is six characters and
  `dosubst("hello%")` is five. Flagging it produced 209 false positives.
- **`DURATION` is a length, not a time of day.** `tests/test3.rem` writes
  `DURATION 48:45` for an event running over two days, and Remind accepts it.
- **`AT` is not the only source of a time.** `include/lunar-eclipses.rem`
  supplies one from a pasted `[utctolocal(...)]` DATETIME, 142 times.
- **Only some `subst_` names are callbacks.** Remind builds `subst_<c>` for a
  *single* character, so `subst_a` is one and `subst_a_alt` is an ordinary
  helper — and `include/lang/` is full of helpers. 45 false positives.
- **`errmsg Please run [filename()] ...`** in `tests/tstlang.rem` made the
  trigger parser read the English "run" as the start of a shell body, and then
  report the rest of the sentence as command injection.

`RULES.md` has the full list.

## Licence

GPL-2.0-only, as Remind is.
