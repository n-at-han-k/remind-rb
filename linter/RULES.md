# Rule backlog

The 100 rule ideas from `book-sections/*.md`, triaged. Ordered by what I would
build next, not by chapter.

The test each rule has to pass: **does Remind stay silent when this is wrong?**
Remind reports `Missing ']'`, `E_NOSUCH_VAR` and `Can't compute trigger`
perfectly well on its own. A linter earns its place only where Remind says
nothing, or says it months later on the day a reminder fires.

Constants are verified against the C source, not taken from the prose. Where a
rule below cites a limit, the file and line that defines it is named.

---

## Tier 1 — security (2) — DONE

Built as one rule, `UnquotedShellSubstitution`: it is the same check on two
commands, and one message serves both.

The only rules in the set where being wrong is a hole rather than a wrong date.

- [x] **RunBodyUnquotedSubstitution** — a `%` sequence or `[expr]` outside shell
      quotes in a `RUN` body. Reminder text is data; unquoted data in a shell
      command is command injection in a calendar.
- [x] **IncludeCmdUnquotedPaste** — the same for `INCLUDECMD`. `examples/astro`
      writes `L="[lessons]"` carefully; nothing enforces that care today.

## Tier 2 — exact, single-file, silent when wrong (10) — DONE

Closed sets and literal comparisons. No cross-file knowledge, no runtime values.

Four of these turned out narrower than the book description implied, and every
narrowing came from the source, the man page or the corpus rather than from
reasoning about it. They are recorded inline below and in the rules' own doc
comments.

Built as ten rule classes, because two pairs are one check each:
`UnquotedShellSubstitution`, `ClauseRequiresAt`, `IftrigWithSatisfy`,
`UnknownSubstitutionSequence`, `InfoSubstitutionWithoutHeader`,
`TextAfterEofMarker`, `UntilBeforeFrom`, `CoordinateNotString`,
`ShellUseWhileRunDisabled`, `LiteralTypeMismatch`.

- [x] **UnknownSubstitutionSequence** — `dosubst.c:820` `default:` emits the
      character and drops the `%`. Silent. Valid set: `A`–`Z` case-insensitive
      (`UPPER(c)` at `dosubst.c:482`), `0`–`9`, `!?@#:_"`, plus `%<Header>`,
      `%(text)`, `%{name}` and the `%*` modifier.
      **Two corrections.** Every letter and every digit is a case, so there is
      no `%z` typo to catch — the rule is really about punctuation and
      unterminated argument forms. And a trailing `%` is *documented*: it
      suppresses the appended newline (`remind.1`; `dosubst("hello")` is 6
      characters, `dosubst("hello%")` is 5). Flagging it produced 209 false
      positives on `tests/`.
- [x] **InfoSubstitutionWithoutHeader** — `%<Name>` with no matching `INFO` on
      the command. `FindTrigInfo` returns NULL and nothing is shipped
      (`dosubst.c:293`), so the body reads `Meeting at ` like a truncation bug.
- [x] **UntilBeforeFrom** — `UNTIL` earlier than `FROM`. **Two corrections.**
      Remind is *not* silent: it warns at parse time, with a separate message
      for `SCANFROM`, which the rule now covers too. And equal dates are a
      legal one-day window that fires — `FROM 1992-01-06 UNTIL 1992-01-06`
      triggers on the day — so the comparison is strict.
- [x] **IftrigWithSatisfy** — `IFTRIG` takes any trigger a `REM` does *except*
      `SATISFY`. Easy to hit by copying a `REM`.
- [x] **TimeZoneWithoutAt** + **DurationWithoutAt** — built as one rule,
      `ClauseRequiresAt`. Both are "this clause needs a time"; the message names
      which clause and why. **Corpus correction:** `AT` is not the only source
      of a time. `include/lunar-eclipses.rem` supplies it from a pasted
      `[utctolocal(...)]` DATETIME, 142 times. A trigger containing any
      bracketed expression is now left alone.
- [x] **LatitudeLongitudeNotString** — built as `CoordinateNotString`. Remind
      has no float type, so `SET $Latitude 45.42` is not a near miss, it is a
      different thing. Out-of-range values produce confidently wrong sunrise
      times.
- [x] **TextAfterEofMarker** — `files.c:421`, exact match on a line of
      `__EOF__`. Everything below is dead text that reads like configuration.
- [x] **CrossTypeEqualityAlwaysFalse** — built as `LiteralTypeMismatch`, which
      also covers the ordering half of **OperandTypeMismatch**: `compare()` in
      `expr.c` makes `==` a constant 0 and `!=` a constant 1 across types, and
      raises `Type mismatch` for `<`, `>`, `<=`, `>=`.
- [x] **ShellUseDefinedWhileRunDisabled** — built as `ShellUseWhileRunDisabled`.
      Confirmed in the source: `userfns.c:280` captures the flag at definition
      and `expr.c:777` re-applies it at every call.

## Tier 3 — exact, worth having, lower frequency (20) — DONE

Built as eleven rule classes, merging where the check is one check:
`ClauseValueRange`, `DateOutOfRange`, `ClauseNeedsFullDate`, `RepeatTrigger`,
`InfoClause`, `TagSyntax`, `BannerPlacement`, `UnknownSpecialType`,
`StringEscape`, `DebugCommand`, `ShellMaxlen`, plus the nesting limit folded
into `UnbalancedBlocks`.

**Four more corpus corrections**, all from `tests/`:

- `DURATION` has no hour ceiling. A duration is a *length*, not a time of day;
  `tests/test3.rem` writes `DURATION 24:45` and `DURATION 48:45` and Remind
  accepts both. Only the minutes are bounded. (12 false positives.)
- `OMIT ... THROUGH ...` takes partial dates on purpose -- it is the omit-range
  syntax, not a reminder's expiry. `OMIT Jun THROUGH July 15` is in
  `tests/test.rem`. (3 false positives.)
- The `SPECIAL` set includes `PostScript`, `PSFile` and `PS`, which rem2ps
  compares `passthru` against and which look like reminder types rather than
  SPECIAL ones. (2 false positives.)
- `AT 13:00AM` really is an error -- `Ill-formed time`, confirmed against the
  binary -- so that one stayed.


`DateLiteral` (built for `UntilBeforeFrom`) already reads Remind's date forms
in any order, so the three date-range rules are mostly wiring. `Trigger` gives
the clause positions the time and priority rules need.



- [x] **TriggerComponentRange** / **DateConstantBeforeEpoch** /
      **DateOutsideRepresentableRange** — merge into one. `BASE 1990` +
      `YR_RANGE 4000` (`custom.h.in:80,86`) gives 1990-01-01 … 5990 exactly.
- [x] **TimeValueRange** — `AT 25:00`, `AT 9:70`.
- [x] **PriorityOutOfRange** — `ParsePriority` (`dorem.c:2143`) is `p<0 || p>9999`
      → `E_2HIGH`. Note: `PRIORITY -1` returns `E_EXPECTING_NUMBER` instead, and
      the message should say so.
- [ ] **IntConstantOutOfRange** — Remind's INT is the platform's C int.
      *Deferred: the bound is the build's `int`, which the linter does not know,
      and a literal that large is vanishingly rare.*
- [x] **InvalidStringEscape** — closed escape set; `\x00` prohibited outright.
- [ ] **TildeBackWithDayComponent** — `~~n` has an implied day component of 1;
      writing both is a contradiction. *Deferred with BackSugarAvailable: both
      need delta/back parsing that nothing else wants yet.*
- [x] **PartialDateAfterFromUntil** — both keywords require a full date.
- [x] **RepeatWithoutFullStartDate** — a repeat counts from a start date.
- [x] **WeekdayWithRepeat** — the weekday picks only the start date; the
      recurrence ignores weekdays. `REM Fri 15 Sep 2025 *10` fires on days that
      are mostly not Fridays.
- [x] **BannerPlacement** — only the last `BANNER` matters.
- [x] **MaxOverdueNotPositive**, **CompleteThroughNotFullDate**
- [x] **TagSyntax** — a comma inside a tag splits it into two nobody meant.
- [x] **DuplicateInfoHeader** — headers are not case-sensitive, so `Url:` and
      `URL:` on one command collide.
- [x] **InfoStringMalformed**
- [ ] **HebrewDateOutOfRange** — *Deferred.* Month lengths are **not** fixed:
      `hbcal.c` recomputes Heshvan and Kislev per year from the year length
      (353/354/355 days), so only "no month has more than 30 days" is decidable
      cheaply, and that catches almost nothing.
- [ ] **MoonPhaseArgumentRange** — closed four-element sets. *Deferred: worth
      building, but `moonphase`/`moondate`/`moondatetime` each take the selector
      in a different position and the payoff is one literal check.*
- [x] **UnknownDebugFlag**, **DebugFlagLeftEnabled**
- [ ] **TranslateCommandForm**, **TranslationFormatSpecifiers** — *Deferred to
      the localization group in Tier 5, where the rest of the TRANSLATE and
      callback rules live.*
- [ ] **ShellMaxlenArgument** — `shell(cmd, 0)` returns nothing and looks exactly
      like a command that produced nothing.
- [x] **UnknownSpecialType** / **SpecialBodyShape** / **DefaultColorFormat** —
      extend the existing `ColorComponentRange`.
- [x] **IfNestingTooDeep** — `IF_NEST 64` (`ifelse.c:19`). Free, given the stack
      `UnbalancedBlocks` already keeps. Nobody will ever hit it.

## Tier 4 — needs machinery that does not exist yet

- [ ] **FunctionRedefinition** — real: `suppress_redefined_function_warning` in
      `userfns.c:204`, and `FSET - name(...)` is the documented escape hatch
      (`WHATSNEW:714`). Sits next to `FunctionArity`.
- [ ] **PushVarsMissingName** — reuses `UnbalancedBlocks`' stack. Subtle and
      worth it: an unlisted assignment leaks past the `POP`, which is the one
      thing the block was there to stop.
- [ ] **CallbackFunctionSignature** / **SubstitutionCallbackSignature** —
      `FunctionArity` inverted: check *definitions* against a table of callback
      names and required arities. `check_subst_args(func, 3)` at `dosubst.c:372`.
- [ ] **WarnSequenceNotDecreasing** / **SchedSequenceNotIncreasing** — literal
      `choose()` sequences only.
- [ ] **EasterdateFromToday** — pattern match on `easterdate(today())` in a
      trigger carrying an offset. Narrow, exact, high value.
- [ ] **SatisfyConstraintNotHoisted** — the strongest single rule in the set and
      the only one with measured numbers behind it: 13.2M evaluations → 482K,
      2.30s → 0.58s. Narrow literal case only (`SATISFY [$Td == 13]` → move the
      13 into the trigger).
- [ ] **UnsatisfiableSatisfy** — needs a small range check over trigger
      components. `$Td == 100` is decidable.
- [ ] **TriggerReuseWithoutScanfrom** — `$T` dataflow between adjacent `REM`s.
- [ ] **MaxSatIterAbsurd**, **SatisfyBoundedByYear**
- [ ] **IncludeRelativePath** — resolves against the working directory, not the
      including file. Works from one directory, fails from another.
- [ ] **SysIncludeAbsolutePath**, **IncludeTargetMissing** (literal paths only)
- [ ] **AddOmitWithoutScanfrom** / **ScanfromTooShort** — the 28-day figure is
      sourced (ch. 4 line 174); the 7-day one for monthly looks extrapolated and
      should be checked before it ships.
- [ ] **RecursionDepthExceeded** — `MAX_RECURSION_LEVEL 1000` (`custom.h:147`).
      Only decidable for literal arguments to simple recursive functions. Real
      work for a rare bug; near the bottom.
- [ ] **MoonriseDatePartUnchecked**, **HebrewMonthName**,
      **HebrewDateNeedsLeftToRightMark**, **MsgsuffixLeadingBackspace**
- [ ] **WorldWritableScript** — a file-mode check rather than a content one, but
      it fits: Remind refuses a world-writable script outright.
- [ ] **QueuedComputedTimeWithoutNoqueue**, **RunOnInIncludedFile**

## Tier 5 — style, off by default

- [ ] **AdvanceWarningWithoutRelativeSubstitution** + **CalendarTextNotLimited**
      — the strongest *pair*: one asks for `%b`, the other asks you to fence it
      in `%"…%"`. Will fire a lot. Opt-in.
- [ ] **TimedReminderWithoutTimeSubstitution** — same family, one axis over.
      Note Remind already warns on `%1`–`%9` without `AT` at warning level
      05.03.04 (`dosubst.c:474`), so scope this to the complement.
- [ ] **BackSugarAvailable** — `REM 1 --1` and `REM ~~1` are the same reminder.
- [ ] **OmitAwareDeltaWithoutOmits** — with an empty omit context `+n` is exactly
      `++n`, so the single sign is a typo or a missing `OMIT`.
- [ ] **WeekdayDayTriggerConfusion** — demoted to informational. `REM Friday 13`
      is the classic misunderstanding but occasionally what someone wants.
- [ ] **SatisfyEvaluatedInForeignZone** — informational; correct, documented and
      reliably surprising.
- [ ] **HardCodedColorsWithoutPsCalGuard**, **CalKeywordVersusEmptyCalendarText**
- [ ] **TkTagNamespace**, **GeneratedFileEdited**, **ConvertedFileHandEdited**,
      **RemindOptionsInterfereWithServerMode**
- [ ] **DebugCommandsCommitted**, **SystemVariableVersusTranslate**
- [ ] **LangidNotTranslated**, **SubstitutionCallbackUnknownSequence**
- [ ] **TodoWithoutCompleteThrough**, **RecurrenceNotExportable**
- [ ] **UnknownTimeZoneName** + **TimeZoneNameCaseOnlyMismatch** — the second
      turns the first's shrug into an actionable message by naming the zone that
      was probably meant.

---

## Blocked on a decision

**Three rules need the invocation, which is not in the file.**
`SortOptionInScriptComment` (`-g`), `InfoHeadersNeedDashPP` (`-pp` vs `-p`) and
`TodoOutsideAgendaMode` (agenda vs calendar) all depend on how the file is run.
They share one prerequisite:

```remind
# remlint:invocation remind -pp -g
```

Build that once and all three work. Skip it and all three are guesswork. Decide
deliberately rather than discovering it three times.

**Five need to see past one file.** `UndefinedVariable`,
`CallbackFunctionMissing`, `AstronomyWithoutLocation`, `RunOnInIncludedFile`,
`FeatureNewerThanTargetVersion`. `FunctionArity` already stays silent on unknown
functions because helpers arrive through `INCLUDE`; `UndefinedVariable` is the
same problem one axis over and worse, since variables outnumber calls. Following
`INCLUDE` is an architecture change, and `INCLUDECMD` *executes*, so it cannot be
followed safely at all. The cheap answer is the `AllowedNames` config already
built for `UnknownSystemVariable`: declare what arrives from outside, lint the
rest.

**FeatureNewerThanTargetVersion needs a column the generator cannot produce.**
It wants "introduced in which version" for every keyword, function and system
variable. `tasks/generate_tables.rb` reads one checkout, so it cannot know.
Either walk the git history of `token.c`/`funcs.c`/`var.c`, or carry a
hand-maintained since-map that will drift. A design decision, not a rule.

**SyntaxRuleNeedsRemind is a linter self-diagnostic, not a per-file offence** —
but it points at a real gap. The `Syntax` rule currently skips silently when
`remind` is not on PATH, which means CI can believe it is syntax-checking when
it is not. That belongs as one warning from the runner.

## Cut

- **RecurringReminderIgnoresOmits** — its own description concedes the default
  "is right for most reminders". A rule that is wrong most of the time teaches
  people to ignore the linter.
- **ScriptFileExtension** — would fire on `examples/astro` and
  `examples/ansitext`, the two files the extractor layer exists to handle.
- **SecretCalendarUrl** — secret detection is its own discipline with its own
  false-positive economics. `trufflehog` already does it.
- **HebrewSunsetOffset** — "Recording the idea here so the next reader does not
  re-derive it" is an honest note, and undetectable. Keep it as a comment in the
  chapter, not a rule.

## A note on sourcing

The book's licence permits verbatim personal copies and expressly reserves the
work from text-and-data-mining. Some of the rule descriptions quote it directly
("Verbatim from the book: …"). Rule doc comments in this gem must not carry that
prose: cite chapter and section, paraphrase the mechanism, and verify the
constant against the C source — which is GPL-2.0 and quotable — so a GPL gem is
not redistributing a book that forbids redistribution.
