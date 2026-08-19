---
title: "Chapter 3: Holidays and Other Exceptions"
rules:
  - name: LocalOmitNonWeekday
    description: >-
      A local OMIT clause inside REM followed by anything but weekday names. The book states the
      restriction flatly — a local OMIT cannot name specific dates or day/month pairs — so `REM
      15 OMIT 1 January AFTER ...` is a parse error waiting to happen.
  - name: OmitAwareDeltaWithoutOmits
    description: >-
      A single-sign delta or back (`+n`, `-n`, `~n`) in a file with nothing omitted. With an
      empty omit context `+n` is exactly `++n`, so the single sign is either a typo for the
      double, or a sign that the OMIT it depends on never got written.
  - name: RecurringReminderIgnoresOmits
    description: >-
      A recurring REM with no SKIP, BEFORE or AFTER in a file that omits dates. Remind ignores
      the omit context by default. That is right for most reminders and wrong for the paydays
      and pickups this chapter is about, and the difference is invisible until a holiday lands
      on one.
---

# Chapter 3: Holidays and Other Exceptions

Quite often, the regular recurrence of an event is disrupted by holidays or other exceptional days. When this happens, the normal recurrence must be suspended or modified.

Remind handles this with the concept of *Omitted Dates*. It keeps a global list of such dates and this global list is called the *omit context*. When Remind starts up, the omit context is empty. To add dates to the omit context, use the OMIT command. This command can take one of three forms:

- `OMIT weekday ...`

<!-- -->

- `OMIT day month`

<!-- -->

- `OMIT day month year`

The first form is called a *weekday omit*. The second is called a *partial omit* and the third is called a *full omit*. Here are examples of each:

    # Weekends are normally holidays
    OMIT Sat Sun

    # New Year's Day is a holiday
    OMIT 1 January

    # This is a special one-time holiday
    OMIT 6 January 2027

Any of the forms can also include a `MSG` clause, in which case it is *also* treated as a `REM` command. The single `OMIT` command on the first line in the following example is equivalent to the two separate commands that follow it:

    OMIT 1 January MSG New Year's Day

    OMIT 1 January
    REM 1 January MSG New Year's Day

Each OMIT command adds an omitted date to the omit context.

Let’s see how the omit context works in practice. 1 January 2026 is a Thursday, so what happens on 1 January 2026 when we run this script?

    OMIT 1 January
    REM Thursday MSG Meeting

If you run that script on 1 January 2026, the result is:

    Reminders for Thursday, 1st January, 2026:

    Meeting

Wait... what? 1 January is omitted! What’s going on?

By default, Remind *ignores* the omit context when calculating the trigger date of the reminder. If you don’t want that, the `REM` command has three keywords that give you three different options:

1.  `SKIP` simply skips the reminder. In this example, the meeting on January 1st won’t happen, and the trigger date will be the following Thursday, January 8th—the date of the next normal recurrence.
2.  `BEFORE` moves the reminder to *before* any block of omitted dates. In this example, BEFORE will move the trigger date to December 31st, 2025.
3.  `AFTER` moves the reminder to *after* any block of omitted dates. In this example, AFTER will move the trigger date to January 2nd, 2026.

Here are examples, with comments explaining what will happen if the script is run on January 1st, 2026:

    OMIT 1 January

    # Triggered January 1st, 2026 as usual
    REM Thursday MSG Meeting

    # Not triggered January 1st, but is triggered January 8th
    REM Thursday SKIP MSG Meeting

    # Triggered December 31st, 2025
    # assuming Remind is run on that date...
    REM Thursday BEFORE MSG Meeting

    # Triggered January 2nd, 2026
    REM Thursday AFTER MSG Meeting

A date of the form *day month year* is said to be *omitted* if one or more of the following is true:

1.  The weekday of the day is an omitted weekday.
2.  The *day* and *month* match a partial omit.
3.  The entire date matches a full omit.

## 3.1 Local OMITs

It is very common to have a number of reminders that are affected if they fall on weekends (for example, paydays) while others are not. Because this is so common, rather than globally omitting weekends, you can have a *local OMIT* clause right within a `REM` command. Here are some examples:

    REM 15 AFTER MSG 15th of every month; delayed after holidays

    REM 15 OMIT Sat Sun AFTER MSG 15th of every month; \
                                  delayed after holidays/weekend

In the second `REM` command, Remind considers Saturday and Sunday to be omitted even if there are no global weekday Saturday or Sunday OMIT entries.

A local `OMIT` within a `REM` command can only be followed by a list of weekday names. You can’t locally omit specific dates or day-month pairs.

## 3.2 Saving and Restoring the Omit Context

Sometimes, certain omitted days such as holidays apply to one block of reminders but not to others. Remind has three commands for manipulating the omit context:

- `PUSH-OMIT-CONTEXT` takes a snapshot of the current omit context (the weekday, partial and full omits) and saves it on a stack.
- `CLEAR-OMIT-CONTEXT` clears out the omit context, starting you off with a blank slate.
- `POP-OMIT-CONTEXT` restores the omit context from the most recent matching `PUSH-OMIT- CONTEXT`. Any changes to the omit context after the most recent `PUSH-OMIT-CONTEXT` are completely reverted by `POP-OMIT-CONTEXT`

For example, suppose August 5th is a holiday for the purposes of your garbage collection date, but not for the purposes of a work meeting. You could do something like this:

    REM Wednesday SKIP MSG Work meeting

    PUSH-OMIT-CONTEXT
    OMIT 5 August
    REM Wednesday AFTER MSG Garbage pickup
    POP-OMIT-CONTEXT

    # At this point, 5 August is no longer in the omit context

## 3.3 Dumping the OMIT Context

For debugging purposes, you can dump the current OMIT context as follows:

    OMIT DUMP

## 3.4 Alternate Forms of Back and Delta

Back in Chapter 2 we mentioned that the delta `++``n` and back `--``n` have alternate forms with single plus or minus signs. Here’s how they differ:

- A delta of `++``n` starts triggering the reminder exactly *n* days before the trigger date. However, a delta of `+``n` starts triggering the reminder *n* days before the trigger date *not counting omitted dates*.
- A back of `--``n` moves the trigger date back by exactly *n* days. However, a back of `-``n` moves the trigger date back by *n* days *not counting omitted dates*.
- An alternate back of `~``n` triggers on the *n*th last day of the month, *not counting omitted dates*.

Here are some examples illustrating the differences:

    REM 1 --1 OMIT Sat Sun MSG The last day of every month
    REM 1 -1 OMIT Sat Sun MSG The last working day of every month

    OMIT 25 Dec MSG Christmas
    REM 26 Dec ++2 MSG Boxing Day %b (start triggering on 24 Dec)
    REM 26 Dec +2 MSG Boxing Day %b (start triggering on 23 Dec)

    REM November 2025 ~~1 MSG The last day of Nov 2025 (Nov 30)
    REM November 2025 ~1 OMIT Sat Sun MSG The last weekday of Nov 2025 (Nov 28)

And one last sweet bit of syntactic sugar: `LASTWORKDAY` is equivalent to `~1` just as `LASTDAY` is equivalent to `~~1`.
