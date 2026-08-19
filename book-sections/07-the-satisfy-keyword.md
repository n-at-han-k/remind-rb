---
title: "Chapter 7: The SATISFY Keyword"
rules:
  - name: SatisfyConstraintNotHoisted
    description: >-
      A SATISFY expression testing a trigger component the trigger itself could pin down. The
      chapter measures it: over 100 000 runs the all-SATISFY form evaluates the expression 13
      214 377 times and takes 2.30s; moving the day into the trigger drops it to 482 026
      evaluations and 0.58s. Same reminder, four times the speed, and the fix is mechanical —
      move the constant into the trigger.
  - name: UnsatisfiableSatisfy
    description: >-
      A SATISFY expression that no date can satisfy. `REM SATISFY [$Td == 100]` costs
      $MaxSatIter iterations and then prints `Can't compute trigger`. It is decidable from the
      literal alone.
  - name: SatisfyBoundedByYear
    description: >-
      A SATISFY expression that stops being true after some date, such as a `$Ty < 2029` term,
      where an UNTIL clause belongs. The book calls it bad practice: `REM 13 UNTIL 2028-12-31
      SATISFY [$Tw == 5]` says the same thing without needing MAYBE-UNCOMPUTABLE to silence the
      warning it would otherwise raise.
  - name: TriggerReuseWithoutScanfrom
    description: >-
      A REM that reads `$T` computed by an earlier REM, where that earlier REM has no SCANFROM.
      Verbatim from the book: computing $T in one REM and reusing it in the next is *almost
      always a bad idea* because it breaks the Remind algorithm. The credit-card example only
      works because of `SCANFROM -7`.
  - name: WeekdayDayTriggerConfusion
    description: >-
      A weekday-plus-day trigger that looks like it means 'that weekday, on that date'. `REM
      Friday 13 MSG Boo!` is the first thing the chapter knocks down: it means the first Friday
      on or after the 13th, not Friday the 13th. The fix is `REM 13 SATISFY [$Tw == 5]`.
  - name: MaxSatIterAbsurd
    description: >-
      SET $MaxSatIter to a value large enough to hit the expression-complexity limit instead.
      Raising it to 2 000 000 000 does not make the reminder computable; it swaps `Can't compute
      trigger` for `Maximum expression complexity exceeded`. Legitimate raises are modest —
      chapter 13 uses 100 000 for Easter/Passover.
---

# Chapter 7: The SATISFY Keyword

We’ve seen in Chapters 2 through 4 that Remind has pretty powerful techniques for computing recurring reminders. But here’s something you can’t do with what you’ve learned so far: Issue a reminder every Friday the 13th.

Your first attempt might be something like this:

    REM Friday 13 MSG Boo!

But this does not work. Because `Friday 13` means to issue the reminder on the first Friday on or after the 13th of a month. So for example, it will be issued on December 19, 2025 which is a Friday, but certainly not a Friday the 13th.

This is where SATISFY can help. To use it, put a clause of the form `SATISFY [``expr``]` just before the `MSG` keyword, like this:

    REM trigger SATISFY [expression] MSG body

Note that the square brackets are literals and must be there. Additionally, `SATISFY` is a special case that does not follow the normal expression-pasting rules; the expression after the `SATISFY` is *not* evaluated when the line is parsed. Instead, it is evaluated *each time* Remind runs the SATISFY algorithm described in Section 7.1 on the next page.

Anyway: here is how you can issue a reminder every Friday the 13th:

    REM 13 SATISFY [$Tw == 5] MSG Boo!

Wait, *what*?

## 7.1 The Operation of SATISFY

Here’s how `SATISFY` works:

1.  The next trigger date is calculated as usual using the other parts of the `REM` trigger specification following the algorithm in Section 2.4 on page 14.
2.  Next, the expression following the `SATISFY` keyword is evaluated. If this expression returns a **true** value, then the trigger date calculated previously is the ultimate trigger date and we are done.
3.  Otherwise, add 1 to the trigger date calculated previously and compute a *new* trigger date that is on or after this date. We then go back to step 2.

The final piece of the puzzle that you need to know is that the funny expression `$Tw` is a *system variable*. All system variables have names starting with `$`. The specific `$Tw` system variable holds the weekday of the *most recently computed trigger date*, where 0 is Sunday and 6 is Saturday. So lets see what happens if you run the previous example on December 1st, 2025.

1.  Remind calculates the trigger date of `REM 13`. It happens to be Saturday, 2025-12-13.
2.  Remind evaluates the `SATISFY` expression, which returns false, because the weekday (`$Tw`) is 6 rather than 5.
3.  Remind adds 1 to the trigger date to get 2025-12-14.
4.  Remind calculates the trigger date of `REM 13` again, but this time *starting from* 2025-12-14. The result is Tuesday, 2026-01-13
5.  Since the `SATISFY` expression is still false, Remind adds 1 and calculates the trigger date of `REM 13` starting from 2026-01-14. The result is Friday, 2026-02-13.
6.  Now the `SATISFY` expression is true, so the final trigger date of the entire `REM` command is 2026- 02-13.

In principle, you can do everything you need just with `SATISFY` and don’t need any other parts of the trigger. For example, this reminder also triggers on Friday the 13th (you need to know that `$Td` is a system variable that holds the day of the month of the most recently calculated trigger date):

    REM SATISFY [$Td == 13 && $Tw == 5] MSG Boo!

However, this is a lot slower because Remind has to step forward one day at a time and evaluate the expression for each day; it cannot take advantage of the optimizations built in to the normal Remind algorithm implementation. Consider the following three reminders:

    REM SATISFY [$Td == 13 && $Tw == 5] MSG Boo!
    REM Friday SATISFY [$Td == 13] MSG Boo!
    REM 13 SATISFY [$Tw == 5] MSG Boo!

If I run the first one 100 000 times on my computer, for the 100 000 days starting on 1990-01-01 and <sup>1 2</sup> ending on 2263-10-17 , it takes Remind 2.30 seconds. The second one takes 0.74 seconds and the third <sup>3</sup> takes 0.58 seconds.

The reason is that the first reminder has to evaluate the `SATISFY` expression for every single day as it steps through them one by one.

The second reminder steps forward by 7 days on each attempt, significantly reducing how often the `SATISFY` expression must be evaluated.

And the third one is even better, stepping forward a month at a time and reducing the `SATISFY` evaluations even further. In fact, over the 100 000 days, the first `REM` has to evaluate the SATISFY expression a total of 13 214 377, times, the second one 1 930 626 times, and the third one 482 026 times.

As a general rule when you’re figuring out how to use `SATISFY`, do as much as you can with the most- specific normal `REM` trigger components. Then add a `SATISFY` expression to refine or filter the results.

## 7.2 SATISFY Iteration Limit

The algorithm description in Section 7.1 on the preceding page is not quite accurate. Remind also imposes an *iteration limit* after which it gives up trying to satisfy the SATISFY expression. Consider the following example:

    REM SATISFY [$Td == 100] MSG Hello!

This SATISFY expression can only be satisfied if the day-of-the-month of the trial trigger date is 100. Since the day of the month can be at most 31, the expression will never be true. If you run the above example, the output will be:

    Can't compute trigger

The system variable `$MaxSatIter` controls how many times Remind will try to satisfy the expression before giving up. By default, it is set to 10 000 and you should probably not change the default.

You can set `$MaxSatIter` using the `SET` command. If you try something like this:

> <sup>1</sup> Yes, 100 000 days is a bit under 274 years. <sup>2</sup> I have a pretty fast computer. <sup>3</sup> In case you are wondering: there are 471 Friday-the-13ths from 1990-01-01 through 2263-10-17, or about 1.7 per year. The first one is 1990-04-13 and the last is 2263-03-13.

    SET $MaxSatIter 2000000000
    REM SATISFY [$Td == 100] MSG Hello!

then the output is a bit different:

    `==': Maximum expression complexity exceeded

In this case, another built-in limit is hit that limits the number of expression-evaluation steps on a given line.

Now, it could happen that you think that you need to use a SATISFY expression that will always return false after some date. This is bad practice and should be avoided, but you can tell Remind that you know what you are doing as follows:

    REM MAYBE-UNCOMPUTABLE 13 SATISFY [$Tw == 5 && $Ty < 2029] MSG Boo!

The SATISFY expression above is true if the trigger weekday is Friday *and* the trigger year is less than 2029. Obviously, it will never be satisfied after 2028. Normally, Remind would issue the “Can’t compute trigger” in that case, but the `MAYBE-UNCOMPUTABLE` keyword suppresses that warning and simply results in the reminder never triggering after 2028.

Of course, as I wrote, this is bad practice. The better approach is to use:

    REM 13 UNTIL 2028-12-31 SATISFY [$Tw == 5] MSG Boo!

## 7.3 Useful Functions and System Variables

The following built-in functions and system variables are very useful within a SATISFY expression:

- `trigdate()` – returns the most-recently computed trigger date, as a DATE object. The system variable `$T` is equivalent to this function.
- `$Ty` – equivalent to `year(trigdate())`
- `$Tm` – equivalent to `monnum(trigdate())`
- `$Td` – equivalent to `day(trigdate())`
- `$Tw` – equivalent to `wkdaynum(trigdate())`
- `$U` – equivalent to `today()`
- `$Uy` – equivalent to `year(today())`
- `$Um` – equivalent to `monnum(today())`
- `$Ud` – equivalent to `day(today())`
- `$Uw` – equivalent to `wkdaynum(today())`

## 7.4 A SATISFYing Gallery

This section is a cookbook of some things that are easy to do with SATISFY, but hard or impossible without it.

#### 7.4.1 The Fifth Weekday of a Month

Back in Section 2.9 on page 18 I mentioned that there was no straightforward way to create a reminder for the fifth Friday of a month, for example. Well, you now have the tools to do it!

First of all, the fifth Friday of a month must be on or after the 29th. However, writing something like:

    REM Friday 29 June MSG Fifth Friday in June!

is not correct. Running this in June 2026, for example, results in a trigger date of Friday, 2026-07-03, which is certainly not in June. We need to add a SATISFY clause that accepts the trigger if and only if the day-of-the-month of the result is at least 29. So this one works:

    REM Friday 29 June SATISFY [$Td >= 29] MSG Fifth Friday in June!

If we run the above in June 2026, the trigger date ends up being Friday, 2028-06-30. That is the first time after 2026 that June has five Fridays in it.

#### 7.4.2 Observed vs. Actual Holidays

American Independence Day is July 4th. So writing a reminder for that is super-easy:

    REM 4 July MSG Independence Day

However, for Federal government employees, the following rules apply: If July 4th is a Saturday, then they get Friday, July 3rd off. If July 4th is a Sunday, then they get Monday, July 5th off. It’s possible to express this with one REM command, but it’s much easier to specify the two cases separately:

    REM 3 July SATISFY [$Tw == 5] MSG Independence Day (observed)
    REM 5 July SATISFY [$Tw == 1] MSG Independence Day (observed)

The first reminder triggers on July 3rd, but *only* if it’s a Friday, and the second triggers on July 5th, but *only* if it’s a Monday.

In case you’re wondering how to handle both cases in a single REM command, here’s one way. Analysis is left as an exercise; convince yourself that this method is slower than the two separate REM commands.

    REM July SATISFY [$Td == 3 && $Tw == 5 || $Td == 5 && $Tw == 1] \
        MSG Independence Day (observed)

#### 7.4.3 US Presidential Election Day

US election day is is defined as the Tuesday after the first Monday in November, or in simpler terms, the first Tuesday on or after November 2nd. Presidential elections happen every 4 years, and mid-term elections are also every 4 years, but offset from presidential elections by 2 years.

All of this can be expressed as follows:

    REM Tuesday 2 November SATISFY [($Ty % 4) == 0] MSG Presidential Election Day
    REM Tuesday 2 November SATISFY [($Ty % 4) == 2] MSG Midterm Election Day

#### 7.4.4 Credit Card Due Date

Suppose your credit card statement is generated on the 15th of every month, and the due date is 21 days later. How can you make a reminder for the due date? At first glance, it seems impossible because with the different lengths of months, the due date could be anywhere from the 5th to the 8th of the following month.

To solve this problem, ask yourself: “If today is a due date, then what condition holds?” And the answer is: 21 days ago, it was the 15th of a month. This immediately leads to the solution:

    REM SATISFY [day($T-21) == 15] MSG Credit Card Payment Due

For my credit card, things are a little more complex. If the normal due date is on a holiday or weekend, then the actual due date is postponed until after the holiday or weekend. So the code I use for my due date is as follows:

    # Calculate 21 days after the 15th:
    REM SCANFROM -7 SATISFY [day($T-21) == 15]

    # Now slide to the first non-omitted day
    REM [$T] OMIT SAT SUN AFTER MSG Credit Card Payment Due

In this example, we see a `SATISFY` clause being used *without* a `MSG`. If you do that, then Remind simply calculates the trigger date and stores it in `$T` without printing a reminder.

This value of `$T` is used in the *next* `REM` command as a basis for issuing the reminder, with the `AFTER` keyword being used to slide the reminder past the weekend or holiday.

Computing `$T` in one `REM` command and then reusing it in a subsequent one is *almost always a bad idea* because it can break the Remind algorithm. Here, I was careful to use a `SCANFROM` clause for the first `REM` <sup>4</sup> command to make sure I didn’t break the algorithm.

> <sup>4</sup> A `SCANFROM` clause is not needed for the second `REM` command because the `AFTER` keyword automatically adjusts the starting point of the Remind algorithm to ensure it gives a correct result.

For example, the due date in July 2025 is 2025-07-07, which is 22 days after June 15th, not 21. That is because July 1st is a holiday in Canada.

If we didn’t have the `SCANFROM` clause in the first `REM` statement, then on 2025-07-07, it would incorrectly calculate the trigger date as 2025-08-05 since the “21 days after the 15th rule” for July would be in the *past* (2025-07-06).

#### 7.4.5 Recycling Date

My plastic recycling pickup happens every second Wednesday. However, if that day *or* the previous Monday or Tuesday is a holiday, then pickup is deferred to Thursday. (If Thursday is also a holiday, pickup still happens on the Thursday.)

The 2-week cycle started on Wednesday, 31 October 2012. Let’s break this down.

First of all, how can we recognize a regular Wednesday pickup? Well, this happens on a multiple of 14 days from 2012-10-31 if and only if none of the Monday, Tuesday or Wednesday is a holiday. Let’s write a function for this:

    # Normal pickups: Every 14 days from the start date,
    # but only if none of Monday, Tuesday or Wednesday is
    # a holiday.
    FSET normal_recycling(x) ( (x-'2012-10-31') % 14 == 0 && \
       !isomitted(x-2) && !isomitted(x-1) && !isomitted(x) )

OK, now how about the delayed recycling pickup? That happens on 1 more than the multiple of 14 days, but only if at least one of the preceding Monday, Tuesday or Wednesday is a holiday. This gives us:

    # Delayed pickups: One day after every 14 days from the start date,
    # but only if at least one of Monday, Tuesday or Wednesday is
    # a holiday.
    FSET delayed_recycling(x) ( (x-'2012-10-31') % 14 == 1 && \
       (isomitted(x-3) || isomitted(x-2) || isomitted(x-1) ) )

Note that the amounts subtracted in the `isomitted()` calls are 1 more than in `normal_recycling` because now we’re looking at the omitted dates from the point of view of Thursday rather than Wednesday.

Finally, recycling happens either on a normal recycling day or a delayed recycling day:

    FSET is_recycling(x) normal_recycling(x) || delayed_recycling(x)

And finally, the REM command is trivial:

    REM SATISFY [is_recycling($T)] MSG Plastic Recycling

If we want to be very fancy, we can add a “ (Delayed)” suffix to delayed pickups like this:

    # If the pickup day is a Thursday, then pickup is delayed
    FSET is_delayed(x) iif(wkdaynum(x) == 4, " (Delayed)", "")
    REM SATISFY [is_recycling($T)] MSG Plastic Recycling[is_delayed($T)]

In the body of a reminder, the system variable `$T` refers to the final trigger date after the SATISFY expression (if present) was satisfied. In fact, Remind does not even begin to parse the body of a reminder until the trigger date has been calculated, so any expressions in the body of a reminder will see the final, calculated trigger date when using any of the related built-in functions or system variables.

#### 7.4.6 End-of-Quarter

Many companies divide their financial reports into quarters, with the quarters ending on 31 March, 30 June, 30 September and 31 December. While this could be implemented as four separate reminders:

    REM 31 March     MSG End of Q1
    REM 30 June      MSG End of Q2
    REM 30 September MSG End of Q3
    REM 31 December  MSG End of Q4

Why not do it in one REM command?

    REM ~1 SATISFY [($Tm % 3) == 0] MSG End of Q[$Tm/3]

Without the SATISFYclause, the reminder would trigger on the last day of every month. But the SATISFY expression is true only for month numbers that are a multiple of 3, hence the whole command triggers only in March, June, September and December. In the body of the reminder, we use expression-pasting to insert the proper quarter number.
