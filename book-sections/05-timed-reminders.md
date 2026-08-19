---
title: "Chapter 5: Timed Reminders"
rules:
  - name: DurationWithoutAt
    description: >-
      DURATION on a reminder that has no AT clause. A duration with no start time has nothing to
      be a duration of; the back-ends have no way to place it.
  - name: TimeValueRange
    description: >-
      An AT time, DURATION or TIME constant outside the values Remind accepts. `AT 25:00` and
      `AT 9:70` are errors Remind reports at run time and a lexer can report at edit time.
  - name: PriorityOutOfRange
    description: >-
      A PRIORITY outside 0–9999. Remind's documented range; the default is 5000, and callbacks
      such as msgprefix compare against $DefaultPrio.
  - name: TimedReminderWithoutTimeSubstitution
    description: >-
      An AT reminder whose body never mentions the time. The queued copy arrives before the
      event, so a body that does not say the time reads as if the event were now. Sibling of
      AdvanceWarningWithoutRelativeSubstitution, one axis over.
  - name: QueuedComputedTimeWithoutNoqueue
    description: >-
      A computed AT time (sunrise, sunset, moonrise, soleq) with no NOQUEUE. Every example in
      the book pairs the two: you want the time in the calendar, not a background process
      printing at sunset. See also chapter 11.
  - name: SortOptionInScriptComment
    description: >-
      A -g sort spec with characters other than a and d. Out-of-grammar characters after -g are
      silently ignored, so a sort you asked for never happens.
---

# Chapter 5: Timed Reminders

So far, all of the reminders we’ve seen have had granularity of one day. In other words, they tell us what *days* events happen, but not what *time*. It’s pretty useless to know that you have a staff meeting every Tuesday if you don’t also know what time the meeting is.

Remind (naturally) allows you to specify the time of events. You do this with the `AT` clause.

## 5.1 The AT Clause

In its simplest form, the `AT` clause is simply the keyword `AT` followed by a time of the form `HH``:``MM` where *HH*:*MM* is a time-of-day in 24-hour clock format. Note that Remind *always* interprets dates and times in the time zone that your computer is set to—unless you tell it otherwise, as we’ll see in a later chapter.

For example, if you have a staff meeting at 3:00PM every Tuesday, you could write a reminder for it like this:

    REM Tuesday AT 15:00 MSG Staff Meeting

If you do not like to use the 24-hour clock format, Remind also lets you write AM/PM style times, so this would work too:

    REM Tuesday AT 3:00PM MSG Staff Meeting

You can also use `.` instead of `:` to separate the hour and minute parts of a time, so `15:00` can also be written `15.00`.

#### 5.1.1 Queuing Reminders

Remind handles timed reminders differently from non-timed ones in the following ways:

- In Calendar Mode, Remind prefixes the reminder with its start time.
- In Agenda Mode, if a timed reminder is scheduled for a time *later* in the day than the effective time (Section 2.11 on page 19), then after Remind prints the day’s agenda, it runs in the background. At the scheduled time, it prints out the reminder.

In the days before most people used a graphical windowing system, printing out reminders in the background in Agenda Mode was pretty cool. Nowadays, however, it’s mostly useless. We’ll see later that Remind has ways to pop up reminders on a graphical system using helper programs. But for now, if you don’t want Remind to run in the background and issue timed reminders, simply invoke it with the `-q` command-line option.

#### 5.1.2 Fine Control over Queuing

If you have some reminders that you *never* want queued, you can use the `NOQUEUE` keyword to prevent them from being queued.

Later on, we’ll see how to get Remind to automatically calculate the time of sunrise and sunset, but for now, let’s suppose you’ve determined that the time of sunset on 30 June 2026 where you live is 20:55 and you want this in your calendar, but you don’t want Remind printing a reminder in the background at sunset. Simply use this:

    REM 2026-06-30 AT 20:55 NOQUEUE MSG %"Sunset%" %! %2

## 5.2 Some Time-Related Substitution Sequences

The previous example use the substitution sequences **%!** and **%2**. This sequence is used for timed reminders; here are some of the more common time-related substitution sequences:

`%1` Replaced with “now”, “*m* minutes from now”, “*m* minutes ago”, “*h* hours from now”, *h* hours ago”, “*h* hours and *m* minutes from now” or “*h* hours and *m* minutes ago” depending on the relationship between the `AT`-time and the effective time (Section 2.11 on page 19).

`%2` Replaced with “at *hh*:*mm*am” or “at *hh*:*mm*pm”

`%3` Replaced with “at *hh*:*mm*” where *hh*:*mm* is the `AT`-time in 24-hour format.

`%!` Replaced with “is” if the trigger time is now or in the future, or “was” if it is in the past.

## 5.3 Advance Warning

We’ve seen in Section 2.5 on page 14 how Remind can trigger reminders several days before the actual event date. Remind has an analogous facility for issuing queued reminders several minutes before the actual event time. Consider these two examples:

    REM Friday AT 11:00 MSG Piano Lesson is %2.
    REM Friday AT 11:00 +30 *10 MSG Piano Lesson is %2.

On Fridays, the first reminder will be queued in the background and then at exactly 11:00, it will be triggered. The second reminder will also be queued, but it will be triggered 30 minutes before the event time (so, at 10:30) and every 10 minutes thereafter until 11:00.

The `+``n` part of an `AT` class is called a *time delta* and the `*``m` part is called a *time repeat*.

Remind handles queued reminders as follows:

- If there is a time delta of *n*, then the reminder is issued *n* minutes before the actual event time.
- If there is a time repeat of *m*, then the reminder is re-issued every *m* minutes until the actual event time.
- If there is a time delta of *n* and a time repeat of *m*, the reminder is *always* triggered on the actual event time, even if *n* is not a multiple of *m*

## 5.4 Specifying Durations

A timed reminder often has an end time as well as a start time. For example, you may have a 45-minute singing lesson every Friday at 9:15AM. You can specify that in either of the following ways:

    REM Friday AT 9:15 DURATION 45 MSG Singing lesson
    REM Friday AT 9:15 DURATION 0:45 MSG Singing lesson

The first form specifies the duration as an integer number of minutes, while the second form specifies it as an `hour:minute` duration. So for example, `DURATION 90` and `DURATION 1:30` are the same.

## 5.5 Syntactic Sugar for a Specific Date and Time

If you have a reminder on a specific date and time, you can use a shortcut syntax to combine the date and time into one token. For example, the following reminders are all equivalent:

    REM 8 January 2027 AT 15:30 MSG Susan's Wedding
    REM 2027-01-08@15:30 MSG Susan's Wedding
    REM 2027-01-08T15:30 MSG Susan's Wedding

The first one spells everything out; the second uses Remind-specific syntax for combining a date and time, and the third uses the official ISO 8601 date/time syntax.

## 5.6 Priority

A `REM` statement can be given a priority with the `PRIORITY` keyword, which looks like this:

    REM trigger PRIORITY p MSG body

The priority *p* can be any integer from 0 to 9999. If a `REM` command has no `PRIORITY` keyword, then the <sup>1</sup> default priority is 5000.

Remind, by default, does not make use of the priority, but it can be used to break ties if you sort reminders in Agenda Mode.

## 5.7 Sorted Output in Agenda Mode

By default, in Agenda Mode, Remind issues reminders in the order they’re encountered in the reminder script. For example, consider this script:

    REM Wed +5 AT 16:30 MSG Piano Lesson %! %b
    REM 10 Jan 2026 +3 MSG Meeting %! %b.
    REM 9 Jan +3 MSG Bob's birthday %! %b.

If we run Remind in Agenda Mode on 2026-01-09, the output is as follows (blank lines have been removed.)

    Piano Lesson is in 5 days' time
    Meeting is tomorrow.
    Bob's birthday is today.

> <sup>1</sup> Actually, the default priority can be changed using something called a *system variable*; see the **remind**(1) man page and look for `$DefaultPrio`

As you see, the reminders come out in the same order they appeared in the script. However, if you supply the `-g` command-line option, then the reminders are sorted by date and time. The output is:

    Bob's birthday is today.
    Meeting is tomorrow.
    Piano Lesson is in 5 days' time

The `-g` option has a number of sub-options to control the sorting; the full syntax of the option is:

- `g[a|d[a|d[a|d[a|d]]]]`

In other words, `-g` may be followed by up to four additional characters; each additional character must be an `a` or a `d`.

The characters have the following meanings:

- If the first character is `a`, then reminders are sorted in ascending order by trigger date. If it is `d`, then the reminders are sorted in descending order by trigger date.
- If the second character is present, then reminders with the same trigger date are further sorted by trigger time, in ascending or descending order depending on whether the second character is `a` or `d`.
- If the third character is present, then reminders with the same trigger date and time are further sorted by priority, in ascending or descending order depending on whether the third character is `a` or `d`.
- If the fourth character is present and is `a`, then untimed reminders are sorted after timed reminders. If it is `d`, then untimed reminders are sorted before timed reminders.

If any character after `-g` is omitted, it is treated as `a`. Therefore, just plain `-g` will sort reminders in ascending order by trigger date; then ascending order by trigger time; then ascending order by priority; and finally timed reminders will be sorted before untimed reminders.
