---
title: "Chapter 4: More Advanced Reminders"
rules:
  - name: AddOmitWithoutScanfrom
    description: >-
      A REM with ADDOMIT and no SCANFROM clause. The book calls the naive form a trap and spends
      a section on it: without SCANFROM the movable holiday is added to the omit context for
      *next* year's occurrence, so reminders that SKIP/BEFORE/AFTER around it silently do the
      wrong thing the day after. Remind 06.01.03+ warns about this; the linter can say it before
      the file is ever run.
  - name: ScanfromTooShort
    description: >-
      A SCANFROM window smaller than the recurrence it protects: fewer than 28 days for an
      annual holiday, fewer than 7 for a monthly one. Below those figures the added omit date
      stops being stable exactly when a nearby reminder needs to skip or slide around it.
  - name: UntilBeforeFrom
    description: >-
      An UNTIL date on or before the FROM date. The reminder can never trigger. Nothing reports
      this — the script just goes quiet.
  - name: PartialDateAfterFromUntil
    description: >-
      FROM or UNTIL followed by anything but a fully-specified date. Both keywords require a
      full date; a partial one is a parse error.
  - name: RepeatWithoutFullStartDate
    description: >-
      A `*n` repeat whose trigger has no fully-specified start date. A repeat counts days from a
      start date; without one there is nothing to count from.
  - name: WeekdayWithRepeat
    description: >-
      A weekday in a trigger that also carries a repeat. The weekday only picks the start date;
      the recurrence then ignores weekdays entirely. `REM Fri 15 Sep 2025 *10` fires on days
      that are mostly not Fridays, which is rarely what the weekday was there for.
---

# Chapter 4: More Advanced Reminders

So far, we’ve covered the basic uses of the `REM` command and covered how holidays are handled with `OMIT`. In this chapter, we’ll look at some of the more advanced ways to use `REM`.

## 4.1 Arbitrary Recurrences

It’s very easy to write a reminder that recurs weekly, monthly or annually in Remind. But some events recur on a different schedule. For example, my garbage and plastic recycling collection day is every <sup>1</sup> second Wednesday. And on the other Wednesdays in between, paper recycling is collected.

You can express arbitrary recurrences with a start date and a *repeat*. Arepeat is simply an asterisk followed by an integer *n*. The reminder is triggered on the start date and then every *n* dates thereafter. Here are my garbage and recycling days:

    REM 2012-11-07 *14 MSG Garbage and plastic recycling
    REM 31 October 2012 *14 MSG Paper recycling

Let’s examine these examples. The first example triggers on 7 November 2012 and then every 14 days thereafter, in perpetuity. The second one triggers on 31 October 2012 and then every 14 days thereafter.

Note that you can write the starting date as either *YYYY-MM-DD* or spell out the day, month and year separately.

If you include a weekday, then it is used *only* to determine the start date and does *not* adjust the recurrence. For example, consider the following reminder:

    REM Fri 15 Sep 2025 *10 MSG Test

The first Friday on or after 15 Sep 2025 is 19 Sep 2025. The reminder will trigger on 19 Sep 2025 and then every 10 days, *regardless* of whether it is a Friday or not.

> <sup>1</sup> Actually, it’s a lot more complicated than that, but for now let’s just pretend it’s every second Wednesday.

## 4.2 Specific Expiry Dates

Quite often, you will have a recurring reminder that starts on a specific date and ends on another date rather than repeating indefinitely. You can use the `UNTIL` keyword to specify an expiry date for a reminder that normally wouldn’t have one.

For example, suppose you have a class every Tuesday, starting on 23 September 2025 with the final class on 9 December 2025. You can express this as follows:

    REM 2025-09-23 *7 UNTIL 2025-12-09 MSG Class

This example triggers every 7 days, starting on 2025-09-23 and finishing on (and including) 2025-12-09.

After the `UNTIL` keyword, Remind expects a fully-specified date like `2025-12-09` or `9 December 2025`.

## 4.3 Specific Starting Dates

Sometimes, you will have a series of reminders that start on a specific date and should not be triggered before that date. Suppose that you have a meeting on the 15th of every month, starting on 2025-06-15 with the last meeting taking place on 2025-11-15. You can express this as follows:

    REM 15 FROM 2025-06-15 UNTIL 2025-11-15 MSG meeting

The `FROM 2025-06-15` means the reminder will never be triggered prior to that date. Note that we *cannot* use a repeat (`*``n`) form here because the gap between the 15th of two subsequent months is not constant.

If we do have a constant repetition, we have options on how to write the reminder. For example, the following are equivalent:

    REM 2025-09-23 *7 UNTIL 2025-12-09 MSG Class
    REM Tuesday FROM 2025-09-23 UNTIL 2025-12-09 MSG Class

Feel free to use whichever you find easier to read and understand.

Just like `UNTIL`, `FROM` expects a fully-specified date like `2025-12-09` or `9 December 2025`.

## 4.4 Movable Holidays

We’ve seen in Chapter 3 how the `OMIT` command lets you mark certain dates as “omitted”, and how Remind can adjust reminders that fall on omitted dates.

But some holidays are movable. For example, Labour Day in Canada is the first Monday in September, and the `OMIT` command has no syntax to express this.

<sup>2</sup> Instead, we can use a normal `REM` command with the `ADDOMIT` keyword.

Here is a naive (but *incorrect*) way to use `ADDOMIT`; I’ll explain why it’s wrong and how to fix it in the next section:

    REM Mon 1 Sep ADDOMIT MSG Labour Day

The `ADDOMIT` keyword tells Remind that if it computes a trigger date for the reminder, then it must add that computed trigger date to the global OMIT context. For example, suppose that today is 15 August 2025 and we run Remind on the following input file:

    REM Mon 1 Sep ADDOMIT MSG Labour Day
    OMIT DUMP

<sup>3</sup> Then the output is:

    Global Full OMITs (1 of maximum allowed 1000):
          2025-09-01
    Global Partial OMITs (0 of maximum allowed 366):
          None.
    Global Weekday OMITs:
          None.
    No reminders.

As you can see, the computed date of Labour Day (2025-09-01) is added to the global OMIT context.

**BUT THIS IS A TRAP.** Because of how the Remind algorithm works, specifying movable holidays in this way is incorrect. Let’s look at this example file:

    REM Mon 1 Sep ADDOMIT MSG Labour Day
    REM 1 AFTER MSG Meeting

If we run this reminder file on 2025-09-01, the output is as follows:

    Reminders for Monday, 1st September, 2025:

    Labour Day

> <sup>2</sup> Earlier versions of Remind used a different mechanism to handle movable holidays, but you should not use them any more. Stick with `ADDOMIT`. <sup>3</sup> Versions of Remind starting from 06.01.03 will issue a warning about the `ADDOMIT` line, so that’s a bit of a spoiler that something is probably wrong.

We get the Labour Day reminder. And the meeting reminder does *not* trigger because the `AFTER` keyword tells Remind to move it until after any holidays. The computed trigger date is thus 2025-09-02.

So let’s run this reminder file on 2025-09-02. What will the output be? The answer is:

    No reminders.

What?? Why wasn’t the delayed meeting triggered?

The answer is that on 2025-09-02, the trigger date for the Labour Day reminder, as calculated by the Remind algorithm, is 2026-09-07, the first Monday in September *that is on or after today*. So the date 2026-09-07 is entered into the global OMIT context, and the meeting reminder has no idea that 2025-09- 01 is in fact supposed to be a holiday.

So how do we fix this? How do we make movable holidays safe?

#### 4.4.1 Safe Movable Holidays

If we think back to the trigger-calculation algorithm in Section 2.4 on page 14, we can see that the trouble occurs because Remind *always* seeks a date *on or after today* that satisfies the trigger. What if we could temporarily pretend that *today* was a bit earlier? Well, we can! And this is the key to fixing the problem.

The `SCANFROM` clause of the `REM` command lets us *pretend* that *today* is actually a few days earlier just for the purposes of calculating a trigger date. A `SCANFROM` clause looks like this: `SCANFROM -``n` where *n* <sup>4</sup> is an integer. This is called a *relative SCANFROM* Let’s look at a concrete example:

    REM Mon 1 Sep SCANFROM -28 ADDOMIT MSG Labour Day
    REM 1 AFTER MSG Meeting

We get very different results when we run this file. On 2025-09-01, we get:

    Reminders for Monday, 1st September, 2025:

    Labour Day

and on 2025-09-02, we get:

    Reminders for Tuesday, 2nd September, 2025:

    Meeting

Huzzah! Success!

> <sup>4</sup> There is also an absolute SCANFROM, but it is almost never used. It was used in older versions of Remind that lacked a relative SCANFROM, but is now considered obsolete.

If we look at the `REM` command with `ADDOMIT`:

    REM Mon 1 Sep SCANFROM -28 ADDOMIT MSG Labour Day

The trigger date on 2025-09-01 is 2025-09-01 (because that happens to be a Monday.) On 2025-09-02, the trigger date is *still* 2025-09-01 rather than the expected 2026-09-07 because `SCANFROM -28` means that the Remind algorithm starts scanning from 2025-09-02 minus 28 days, or 2025-08-25. In fact, the trigger date *remains* 2025-09-01 until Remind is run on 2025-09-30, 29 days after 2025-09-01. That is because in each case, the Remind algorithm considers “today” to be the *actual* run date *minus* 28 days.

`SCANFROM` thus ensures that the addition to the omit context stays stable for any reminders within 28 days of the omitted date. Since typically, there are no long blocks of omitted days, it is very likely that any reminder further than 28 days from the omitted day won’t be affected by it.

For stable movable omitted dates, observe the following rules of thumb:

- For *annually* recurring holidays, use `SCANFROM -28`
- For *monthly* recurring holidays or exceptions, use `SCANFROM -7`

In both cases, the `SCANFROM` amount should be sufficiently large to make sure that omitted days have the correct effect on subsequent `REM` commands.
