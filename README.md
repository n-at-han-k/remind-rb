# remind-rb

Ruby bindings for [Remind](https://dianne.skoll.ca/projects/remind/), through
Fiddle.

```ruby
require "remind"

Remind.today = Date.new(2026, 8, 19)

reminder = Remind.parse("REM Mon 13 SKIP OMIT Sat Sun MSG payday")
reminder.summary                 # => "payday"
reminder.occurrences.first(3)    # => Remind's own trigger dates
reminder.weekdays                # => ["MO"]

Remind.evaluate("moonphase(today())")   # => 46
Remind.evaluate("trigger(today() + 7)") # => "26 August 2026"
```

## Why

Remind's trigger language is bigger than it looks. `REM Mon 13` is not the
second Monday of the month, it is the Monday of the week the 13th falls in.
`REM Wed Thu 15` fires once, on whichever of those weekdays comes first on or
after the 15th. Then there are `SKIP`, `BEFORE`, `AFTER`, `OMIT`, `SCANFROM`,
`UNTIL`, `*n` repeats and back-counted deltas — the manual works through
eighteen examples before it reaches the exceptions.

Every program that has read reminder files with regular expressions has got
part of it wrong. These bindings do not read it at all: `ParseRem` parses the
trigger, `ComputeTrigger` says which dates it fires on, and `DoSubst` renders
the message. What is on the Ruby side is a translation of names, and nothing
about the language.

## Layout

| Path | What it is |
| --- | --- |
| `remind-v06.02.10/` | the Remind release these bindings bind, vendored unchanged |
| `ext/remind/shim.c` | the only C in the gem: struct accessors, and the sequence in `DoRem` |
| `lib/remind/builder.rb` | builds the sources into a shared library, with the flags `./configure` chose |
| `lib/remind/native.rb` | the dlopen'd library: functions, globals, constants |
| `lib/remind/runtime.rb` | the startup `InitRemind` does before it looks at argv |
| `lib/remind/session.rb` | a live interpreter: `today =`, `evaluate` |
| `lib/remind/reminder.rb` | one `REM` line: its fields, its message, its dates |
| `lib/remind/source.rb` | a reminder file, with continuations joined and `INCLUDE`s followed |
| `.github/workflows/` | `cross-compile.yml` builds the platform gems; `test.yaml` runs the suites |
| `lib/rem2ics/`, `exe/rem2ics` | the converter — see [docs/rem2ics.md](docs/rem2ics.md) |
| `lib/remlint/`, `exe/remlint` | RemLint, a style linter for reminder files — see [docs/remlint.md](docs/remlint.md) |

Three gems share this `lib/`, the way ratalada's three share theirs:
`remind-rb`, `rem2ics` and `remlint`, each with its own gemspec at the root and
its own version, all developed from one bundle.

## Installing

```
gem install remind-rb
```

That is an unpack, not a build. Remind is C, and compiling it means
`./configure`, `make` and a toolchain — a packaging problem, solved once in CI
rather than on every machine that installs the gem.
`.github/workflows/cross-compile.yml` builds the shared library on each
platform and packages a gem with the library already inside; RubyGems serves
the one matching yours. The library is built without readline, so it asks the
loader for nothing a plain system lacks.

The source gem carries the vendored Remind sources and no library, for a
platform CI does not cover: `gem install remind-rb --platform=ruby` then
`rake compile`. `REMIND_LIBRARY` points the bindings at a library built
anywhere else.

## Working on it

```
bin/setup                  # bundle, compile, install git hooks
rake compile               # ./configure + one -fPIC -shared compile
bin/test                   # every suite in the repository
rake native[x86_64-linux]  # package a precompiled gem for one platform
```

The compile reads the compiler, the flags, the feature macros and the
libraries to link out of the `src/Makefile` that `./configure` generated, and
adds `-fPIC -shared` and `ext/remind/shim.c`. It writes
`lib/remind/libremind.so` — where a precompiled gem carries it, so a checkout
and an installed gem look the same to everything above.

## Versioning

`6.2.10.0` is Remind `06.02.10`, packaged for the first time. The first three
segments say which Remind is inside; the fourth is ours, bumped for changes on
the Ruby side against that same release:

```
bin/increment-version            # 6.2.10.0 -> 6.2.10.1
bin/increment-version 06.03.00   # track a newly vendored release -> 6.3.0.0
```

The second form refuses to name a release whose sources are not vendored, so
the version cannot claim a Remind that is not there.

## Releasing

CI builds the platform gems and uploads them; publishing is deliberate:

```
bin/release-gem
```

It refuses to publish a version that is not ahead of what is on RubyGems,
builds the source gem locally, downloads the precompiled gems from the latest
green `cross-compile.yml` run, and pushes all of them — tolerating anything
already published, so a half-finished release can simply be re-run.

## The two things to know

**Fiddle, not a C extension.** There is nothing to extend: Remind's sources
compile into a shared library as they are, and everything worth calling is a
plain function over ints and pointers. `ext/shim.c` exists for two things
Fiddle cannot do — reading a 30-field struct without hard-coding byte offsets,
and running the six-call sequence `DoRem` uses to parse a line — not because
Fiddle needed help calling anything.

**The state is process-wide.** Remind keeps "today" in a global, because a
program that runs once and exits has no reason not to. `Remind.today =` moves
the ground under every calculation, deliberately: a reminder that says `Mon`
means a different date tomorrow than it does today, and pinning the date is
what makes a conversion reproducible. Calls into the library are serialised
behind one lock, whether they came from one `Session` or several.

## Licence

GPL-2.0-only — see [LICENSE](LICENSE).

Not a choice so much as a consequence: this gem vendors Remind's complete
source tree, compiles it, and ships the result, so what it publishes is a
distribution of Remind. `ext/remind/shim.c` is written against Remind's own
headers and links into one shared library with its objects. Remind is
Copyright (C) 1992-2026 Dianne Skoll; the bindings around it are Copyright (C)
2026 Nathan Kidd, under the same terms.
