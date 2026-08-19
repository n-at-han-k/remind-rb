---
title: "Chapter 8: Some Callback Functions"
rules:
  - name: CallbackFunctionSignature
    description: >-
      A Remind callback function defined with the wrong number of arguments. Remind calls these
      by name and by shape. A `msgprefix(p, q)` is simply never called, and nothing says so —
      the prefix just does not appear.
  - name: CallbackFunctionMissing
    description: >-
      OMITFUNC, WARN or SCHED naming a function the file never defines. The clause silently does
      nothing useful, so the reminder quietly falls back to plain behaviour.
  - name: WarnSequenceNotDecreasing
    description: >-
      A WARN function whose choose() sequence is not monotonically decreasing, or does not end
      in 0. Remind stops calling the function the moment the absolute values stop decreasing, so
      the later warnings are dropped without a word. Ending in zero is the documented style.
  - name: SchedSequenceNotIncreasing
    description: >-
      A SCHED function whose literal sequence does not yield times that keep moving forward.
      Remind stops calling the function the moment the sequence stops increasing, so the queued
      reminder silently loses every nudge after that point.
  - name: MsgsuffixLeadingBackspace
    description: >-
      A msgsuffix that does not start with char(8) while $AddBlankLines is untouched. Without
      the backspace the suffix lands on its own line, which is almost never what a suffix is
      for.
---

# Chapter 8: Some Callback Functions

Sometimes, rather than using `SATISFY` for complicated reminders, a different approach that uses a function to manipulate the OMIT context is an easier way to write reminders. The `OMITFUNC` keyword lets you do this. We’ll also look at a couple of other keywords that give you finer-grained control over advanced warning and reminder queuing. And after that, we’ll look at unrelated callback functions that let you modify the appearance of reminders.

## 8.1 OMITFUNC

Recall the recycling day example in Section 7.4.5 on page 63. It required a pretty complicated `SATISFY` expression to get it to work properly. But really, the dead-simple reminder:

    REM 2012-10-31 *14 AFTER MSG Plastic Recycling

is *almost* correct. The only problem is that for this specific reminder, we want the Wednesday to be considered OMITted if it is omitted *or* the previous Tuesday is *or* the previous Monday is. A small adjustment fixes the problem:

    # Return true if: Today is a Wednesday, and
    # either today, yesterday or the day before yesterday is a holiday.
    FSET recycle_holiday(x) wkdaynum(x) == 3 && \
         (isomitted(x) || isomitted(x-1) || isomitted(x-2))

    REM 2012-10-31 *14 OMITFUNC recycle_holiday AFTER MSG Plastic Recycling

Here’s how it works: If a `REM` command has an `OMITFUNC` clause, then *instead* of looking in the global OMIT context to see if a date is OMITted, Remind calls the function named in the `OMITFUNC` clause with a single argument of type DATE. The function should return **true** if Remind should consider the date to be OMITted, or **false** if it should not.

In our example, the function returns true if the date is a Wednesday, and if *any* of the date itself, the previous day, or the day before that is OMITted. In other words: If the Monday, Tuesday or Wednesday is OMITted, the function returns true. Otherwise, it returns false.

We also ensure that the function only returns true if the trigger day is a Wednesday, because if a Wednesday and a Thursday happen to be holidays, collection still takes place on the Thursday.

The solution using `OMITFUNC` is faster than the `SATISFY` solution in Section 7.4.5 on page 63 because the built-in Remind algorithm does more of the “heavy lifting” and fewer expression evaluations are required. I also find it easier to understand, though you should pick whichever way you find easiest.

## 8.2 The WARN Keyword

Recall the delta feature (Section 2.5 on page 14) that (in Agenda Mode) gives you advance warning of an upcoming reminder. The `WARN` keyword gives you more control over exactly which days the advance warning is issued.

The `WARN` keyword must be followed by the name of a function. This function is passed a single argument of type INT and must return an INT. To figure out the days on which to give advance warning, Remind calls the `WARN` function successively with the arguments 1, 2, 3, ... The return value is interpreted as follows:

- If the return value *n* is positive, then the reminder is triggered exactly *n* days before its trigger date, just as if a delta of `++``n` had been supplied.
- If the return value *n* is negative, then the reminder is triggered *m* days (where *m* = \|*n*\|) before its trigger date not counting OMITted dates, just as if a delta of `+``m` had been supplied.
- If an error occurs during the evaluation of the function, or it returns a non-INT, or the absolute values of the return values are not monotonically decreasing, then Remind stops calling the function and subsequently only triggers the reminder on its actual trigger date.
- As a matter of style, the final return value from the `WARN` function should be zero, but even if this is not the case, Remind *always* triggers the reminder on its actual trigger date.

With all of that in mind, consider this example:

    FSET wfun(x) choose(x, 5, 3, 1, 0)
    REM 4 July WARN wfun MSG American Independence Day is %b.

As `wfun` is called with the successive values 1, 2, 3, ... it returns 5, 3, 1 and 0. So the reminder is triggered 5 days before, 3 days before, 1 day before and on the day of 4 July. (In other words, it is triggered on 29 June, 1 July, 3 July and 4 July.)

## 8.3 The SCHED Keyword

Just as `WARN` gives you more control over a date delta, `SCHED` gives you more control over a time delta for queued reminders. The `SCHED` keyword (as with `WARN`) must be followed by the name of a function, which is successively called with the arguments 1, 2, 3, ... The result of the function controls when the queued reminder is issued.

The return value must be an INT or a TIME. It is interpreted as follows:

- If the return value is a negative INT, then the reminder is issued that many minutes before the trigger time.
- If the return value is a positive INT, then the reminder is issued that many minutes after it was previously issued.
- If the return value is a TIME, then the reminder is issued at that time.

Again, an example will probably serve to clarify:

    FSET sfun(x) choose(x, -60, 30, 15, 10, 3, 1, 1, 1, 1, 0)
    REM AT 13:00 SCHED sfun MSG Meeting %2.

When this reminder is queued, it will first be triggered at 12:00 (which is 13:00 - 60 minutes). It will then be triggered 30 minutes later, at 12:30. Then 15 minutes after that at 12:45, then at 12:55, 12:58, 12:59, 13:00, 13:01 and 13:02. Note that a `SCHED` function can request that Remind continue to trigger a queued reminder even *after* the trigger time.

As with `WARN`, if the `SCHED` function yields an error, does not return a TIME or an INT, or the sequence of times is not monotonically increasing, Remind stops calling it.

## 8.4 Prefix and Suffix Callback Functions

If you define certain user-defined functions, then Remind calls them to prefix and/or suffix the text that normally appears in a reminder. These are called *callback functions* and the four that you can use to modify how reminders appear are:

- `msgprefix(``priority``)` – If this function is defined, it is called with a single INT argument that is the priority of the `REM` command being executed. It must return a string, and that string is prefixed to the reminder when the reminder is output.

  `msgprefix` is called *only* in Agenda Mode.

- `calprefix(``priority``)` – If this function is defined, it is called with a single INT argument that is the priority of the `REM` command being executed. It must return a string, and that string is prefixed to the reminder when the reminder is output.

  `calprefix` is called *only* in Calendar Mode.

- `msgsuffix(``priority``)` – If this function is defined, it is called with a single INT argument that is the priority of the `REM` command being executed. It must return a string, and that string is suffixed to the reminder when the reminder is output. Note that normally, Remind leaves a blank line after a reminder and the result of `msgsuffix` will appear on a new line. If you want it to appear on the *same* line as the reminder, make sure the return value of `msgsuffix` begins with a backspace character, or `char(8)`.

  `msgsuffix` is called *only* in Agenda Mode.

- `calsuffix(``priority``)` – If this function is defined, it is called with a single INT argument that is the priority of the `REM` command being executed. It must return a string, and that string is suffixed to the reminder when the reminder is output.

  `calsuffix` is called *only* in Calendar Mode.

Here’s an example of how you might use these functions. I have set the system variable `$AddBlankLines` to 0 to suppress the blank lines that normally appear between reminders.

    # $DefaultPro is the default priority of a REM statement
    # and is set to 5000 by default
    SET $AddBlankLines 0
    FSET msgprefix(p) iif(p > $DefaultPrio, "URGENT: ", \
                          p < $DefaultPrio, "Non-urgent: ", \
                          "Normal: ")
    REM PRIORITY 9000 MSG Buy cat food
    REM PRIORITY 5000 MSG Check lottery ticket
    REM PRIORITY 1000 MSG Polish shoes

The output of this script in Agenda Mode is:

    URGENT: Buy cat food
    Normal: Check lottery ticket
    Non-urgent: Polish shoes

## 8.5 Sortbanner

Another callback function that you can define is `sortbanner`, which takes a single DATE argument. If you use the `-g` command-line option to sort reminders, then `sortbanner` is called just before each block of reminders on a different date. The result is passed through the substitution filter and printed.

This is most easily explained with an example. Consider this script `sorted.rem`:

    SET $AddBlankLines 0
    # Switch off the normal banner
    BANNER %
    REM 11 March 2026 ++1 MSG Not so important
    REM 17 March 2026 ++7 MSG Way in the future
    REM 10 March 2026 MSG Important Reminder
    REM 11 March 2026 ++1 MSG Not so important - B

    FSET sortbanner(x) iif(x == today(), \
                           "***** THINGS TO DO TODAY *****", \
                           "%_----- Things to do %b -----")

If we run this script on 10 March 2026 as follows:

    $ remind -g sorted.rem 2026-03-10

Then the output is:

    ***** THINGS TO DO TODAY *****
    Important Reminder

    ----- Things to do tomorrow -----
    Not so important
    Not so important - B

    ----- Things to do in 7 days' time -----
    Way in the future

Note that the second `iif` return value starts with `%_`, which causes the substitution filter to emit a newline. This spaces the blocks of reminders apart from one another.
