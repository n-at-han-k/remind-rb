---
title: "Chapter 10: TODOs"
rules:
  - name: CompleteThroughNotFullDate
    description: >-
      COMPLETE-THROUGH followed by anything but a YYYY-MM-DD date. It is the starting point of
      the whole trigger calculation for a TODO; a partial date makes the reminder start from the
      beginning of time instead.
  - name: TodoWithoutCompleteThrough
    description: >-
      A TODO reminder with no COMPLETE-THROUGH clause. Remind then starts the algorithm at
      1990-01-01, so the TODO is overdue by decades on its first run — usually a sign the clause
      was meant to be filled in and never was.
  - name: MaxOverdueNotPositive
    description: >-
      MAX-OVERDUE with a non-positive or non-integer argument. The clause counts days past the
      due date; zero or negative turns the nagging off in a way that reads as if it were
      configuring it.
  - name: TodoOutsideAgendaMode
    description: >-
      A TODO reminder in a file only ever rendered as a calendar. TODO semantics — the nagging,
      the overdue tail — exist only in Agenda Mode. In a calendar a TODO is just an ordinary
      event, which makes the keyword a lie.
---

# Chapter 10: TODOs

Remind is really designed to remind you about events and is not a TODO manager or a task manager. However, it has limited features that do support TODOs.

## 10.1 The TODO Keyword

A TODO is a normal `REM` command, but it includes the `TODO` keyword. The syntax looks like this:

    REM TODO trigger [COMPLETE-THROUGH yyyy-mm-dd] [MAX-OVERDUE n] MSG body

The `TODO` keyword modifies the behavior of `REM` as follows:

- Rather than using today’s date as the starting point of the Remind algorithm (Section 2.4 on page 14), Remind uses the `COMPLETE-THROUGH` date plus one day. If there is no `COMPLETE- THROUGH`, then Remind starts calculating the trigger date from the *beginning of time*, 1990-01-01.
- If the calculated trigger date is in the past, the reminder is nevertheless triggered. However, if there is a `MAX-OVERDUE n` clause, then the reminder is only triggered for *n* days past its due date.

Examples should clarify this. Suppose you pay rent on the first day of every month, and you are fully paid-up through 2026-09-01. Then you might use this reminder:

    REM TODO 1 +7 COMPLETE-THROUGH 2026-09-01 MSG %"Rent%" %! due %b.

Let’s see what happens if we run Remind in Agenda Mode on the previous script on various dates.

    # 2026-09-01
    No reminders.

    # 2026-09-27
    Rent is due in 4 days' time.

    # 2026-10-01
    Rent is due today.

    # 2026-10-03
    Rent was due 2 days ago.

    # 2026-10-15
    Rent was due 14 days ago.

Note a few points:

- The reminder is *not* triggered on 2026-09-01. In the absence of `TODO` and `COMPLETE-THROUGH`, it would have been. However, the presence of `TODO` and the fact that it is marked complete through 2026-09-01 means that the calculated trigger date is 2026-10-01, so the reminder is not triggered on 2026-09-01.
- On 2026-09-27 and 2026-10-01, the reminder is triggered as usual.
- On 2026-10-03 and 2026-10-15, the reminder is still triggered *even though the trigger date is in the past*. Essentially, Remind nags you to complete a TODO until you update the `COMPLETE-THROUGH` date to indicate that you have done it. You can limit the number of days that Remind nags you with a `MAX-OVERDUE` clause. For example, if you use `MAX-OVERDUE 15`, then Remind will stop nagging you about a TODO that is more than 15 days late, on the assumption that it’s pointless and you have abandoned the task.

## 10.2 TODOs and Calendar Mode

TODO-style reminders are treated specially only in Agenda Mode. In Calendar Mode, they appear in the calendar exactly as any normal event would.
