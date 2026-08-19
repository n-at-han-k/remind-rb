# rem2ics

Reminder files to iCalendar, built on the [remind-rb](../README.md) bindings.

```
$ rem2ics --date 2026-08-19 ~/.reminders > calendar.ics
$ rem2ics --help
Usage: rem2ics [options] [file...]
    -d, --date DATE     Convert as of this date (default: today)
    -n, --horizon COUNT How many occurrences to check a recurrence rule against
    -o, --organizer ADDRESS
```

This is a port of Martin Michel's `remmy.pl`, and the interesting difference is
not that it is Ruby.

## The judgement it makes

A recurring reminder should become one event with an `RRULE`, so the calendar
repeats it for ever. The trouble is that Remind's trigger language and
iCalendar's `RRULE` overlap without either containing the other. `REM 15` and
`FREQ=MONTHLY;BYMONTHDAY=15` are the same thing. `REM 1 Mar SKIP OMIT Sat Sun`
is not any `RRULE`: it means "1 March, unless that is a weekend, in which case
not at all", and no `BY*` part says that.

Previous converters guessed. This one guesses and then **checks**: the
candidate rule is expanded with ice_cube and compared, occurrence by
occurrence, against the dates Remind itself computes.

- Where they agree, the event carries the rule, and recurs for ever, correctly.
- Where they disagree, the event carries Remind's own dates as `RDATE`s:
  finite, but not wrong anywhere.

That check is the whole reason to build this on bindings. Without Remind in the
process there is nothing to check against.

```
$ rem2ics --date 2019-01-20 examples/remmy-triggers.rem | grep -E 'SUMMARY|RRULE'
SUMMARY:1st Monday after 15th of every month in 2020
RRULE:FREQ=MONTHLY;UNTIL=20201231;BYDAY=MO;BYMONTHDAY=15,16,17,18,19,20,21
```

`remmy.pl` renders that same reminder as `BYDAY=+3MO` — the third Monday —
which is a different day in any month whose 1st is a Monday. The window form
above is what Remind actually means, and it is emitted only because expanding
it matched.

`examples/` at the repository root holds that comparison: `remmy-triggers.rem` is remmy's own test
input, and `remmy-reference.ics` is what remmy makes of it.

## What maps to what

| Reminder | iCalendar |
| --- | --- |
| the trigger | `DTSTART`, and `RRULE` or `RDATE` |
| `MSG`, rendered in Remind's CAL mode | `SUMMARY` — where a `%"…%"` title is honoured |
| `MSG`, rendered normally | `DESCRIPTION` |
| `AT` | the time on `DTSTART` |
| `DURATION` | `DTEND` |
| `+n` on the trigger | `VALARM`, n days before |
| `+n` on `AT` | `VALARM`, n minutes before |
| `RUN`, `CAL`, `PS`, `SATISFY` | nothing — they are not appointments |

## Known limits

- **It converts from a date forwards.** `DTSTART` is the first occurrence on or
  after the day being converted, not the reminder's first ever occurrence. A
  reminder with nothing left to fire — `REM Tue Aug 2018` read in 2019 — is
  dropped.
- **One message per event.** Remind expands `%b` and friends per occurrence;
  an event has one `SUMMARY`. It is rendered as of the day the event starts.
- **Zones are the reader's.** Times are local wall-clock, with no `TZID`, which
  is what a reminder file says.
- **`INCLUDECMD` is not followed.** It runs a shell command, and converting
  somebody else's reminder file should not execute what is in it.

## Licence

GPL-2.0-only — see [LICENSE](../LICENSE).

rem2ics runs entirely through remind-rb, which is Remind, so it carries
Remind's licence. Copyright (C) 2026 Nathan Kidd; Remind itself is Copyright
(C) 1992-2026 Dianne Skoll.
