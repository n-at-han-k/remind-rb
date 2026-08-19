---
title: "Chapter 2: File Structure and Basic Reminders"
rules:
  - name: AdvanceWarningWithoutRelativeSubstitution
    description: >-
      A REM with a delta whose body never says when the event actually is. Section 2.5's worked
      example: `REM 16 July ++10 MSG Jane's birthday.` prints `Jane's birthday.` on 8 July with
      nothing to say the birthday is eight days off. The delta is only useful if the body
      reports the distance; `%b` is the idiomatic fix.
  - name: CalendarTextNotLimited
    description: >-
      A relative-date substitution in a body with no %" ... %" limit. `Bob's birthday is today`
      is right in Agenda Mode and wrong in a calendar box, where only the name should appear.
      Pairs with AdvanceWarningWithoutRelativeSubstitution: the first asks for %b, this one asks
      you to fence it.
  - name: UnknownSubstitutionSequence
    description: >-
      A % sequence in a reminder body that is not one Remind substitutes. A stray `%` is
      silently eaten or turned into something unexpected, and the mistake only shows up in
      output, on the day the reminder triggers.
  - name: TextAfterEofMarker
    description: >-
      Commands after a line consisting of exactly __EOF__. Remind stops reading there.
      Everything below is dead text that reads like live configuration.
  - name: TriggerComponentRange
    description: >-
      A year, month day, or repeat outside the range a trigger-spec allows. Remind rejects the
      out-of-range value, or the reminder can never trigger. Both are cheap to catch without
      running the file.
  - name: BackSugarAvailable
    description: >-
      A `1 --n` trigger that has shorter sugar: `~~n`, LASTDAY or LASTWORKDAY. `REM 1 --1` and
      `REM ~~1` are the same reminder; the sugar also fixes up the month and year for you, which
      the hand-written form does not.
  - name: TildeBackWithDayComponent
    description: >-
      A `~~n` or `~n` back combined with an explicit day component. The tilde form has an
      implied day component of 1; writing both is a contradiction Remind will not resolve the
      way the author expects.
  - name: BannerPlacement
    description: >-
      More than one BANNER command, or a BANNER after the first REM. Only the last BANNER before
      output matters; a second one silently wins over the first, and one written below the
      reminders reads as if it applied to them.
---

# Chapter 2: File Structure and Basic Reminders

This chapter will give you the basics of what a Remind script looks like and introduce you to writing basic reminders.

## 2.1 The Structure of a Remind Script

A Remind script is a plain text file consisting of a sequence of lines. There are three types of lines in a Remind script:

1.  *Commands* - These are lines that actually do something.
2.  *Comments* - These are notes for yourself that are ignored by Remind.
3.  *Blank Lines* - These lines are ignored.

Remind reads a script from beginning to end. However, if Remind encounters a line in the script containing exactly the following:

    __EOF__

(that is, two underscores followed by EOF and two more underscores and then a newline) then it stops reading the script at that point and ignores everything after the `__EOF__` marker.

#### 2.1.1 Commands

You’ve already seen one command so far: The `REM` command. This command, in fact, is the most powerful and complicated command in Remind’s repertoire.

Remind has many other commands besides `REM` and you’ll be introduced to them in due course. This chapter will be devoted almost entirely to the `REM` command.

#### 2.1.2 Comments

Comments are little notes you can leave for yourself in the reminder file. Remind ignores them. Any line <sup>1</sup> that begins with “`#`” or “`;`” is a comment and is ignored by Remind. Here are examples of comments:

    # This line starts with a #.  Remind will ignore it.
    ; This one starts with a semicolon.  It's also ignored.

You might wonder why a calendar program needs comments. Trust me, when you do something very tricky and are immensely pleased with yourself, you owe an explanation to some poor sap who reads the Remind script and has to understand your trickiness. Especially when the poor sap is likely to be you in six months’ time.

#### 2.1.3 Blank Lines

Blank lines are ignored. I tried to think of something witty to write here, but I drew a blank.

#### 2.1.4 Continued Lines

It may happen that you have a very long line in your Remind script—one that is uncomfortably long. You can continue a logical line across multiple physical lines in your Reminder file by ending all but the last physical line with a backslash. Here is an example:

    REM 10 December MSG OK, this is a pretty long line. \
    It might be best to split it across multiple lines. \
    Looks like three physical lines suffice.

Make sure there’s no whitespace after the backslash.

When Remind processes continued lines, it removes the trailing backslash but *not* the newline, and smooshes the result together. So it’s best to continue a line in a place where a space naturally appears and not in the middle of a word. Otherwise that embedded newline will cause chaos. Note, however, that in the *body* of a reminder (the body is the part that comes after `MSG`), Remind will *remove* any embedded newlines. That is why in the previous example, I left a space before the backslash. Otherwise, the sentences would have been squashed together with no spaces after the periods. This removal of the newline only happens in the body of a reminder and not anywhere else.

Remind does not impose any specific limit on the length of a logical (or physical) line. If you want a reminder on March 14th (π Day) consisting of the first ten million digits of π, have at it. Make your line as long as you want.

Of course, there is an ultimate limit, that being the amount of memory in your computer. So perhaps it’s best to avoid being reminded of the first trillion digits of π, unless you have a very large computer indeed.

> <sup>1</sup> Actually, any line whose first non-whitespace character is “`#`” or “`;`”

#### 2.1.5 Character Set and Encoding

Remind is not particularly fussy about the character set or encoding you use in your Remind script, except that it must be a superset of ASCII. All Remind commands are plain ASCII, but you can use whatever you like in the body of a reminder.

However, almost all modern UNIX and Linux systems use the Unicode character set and the UTF-8 encoding. Many of the Remind scripts that ship with Remind assume a UTF-8 encoding, so in practice you need to use the Unicode character set with UTF-8 encoding. If you’re lucky enough to speak a language like English that doesn’t need funny characters like ô or Ł or א, then you can get away with ASCII.

#### 2.1.6 Case Sensitivity

Remind is case-insensitive almost everywhere. I’ll point out the few places that are case-sensitive when we get there, but in your scripts, Remind doesn’t care if you spell it `REM` or `Rem` or `rem`. Similarly, you can use `JUNE` or `June` or `june`... whatever strikes your fancy.

## 2.2 Running Remind

Remind has four major modes of operation, although you will almost always use one of the first two modes listed below:

1.  **Agenda Mode** is the default mode of Remind. In Agenda Mode, Remind runs your script once and prints any reminders that happen to be triggered today.

2.  **Calendar Mode** is used to create calendars. In Calendar Mode, Remind runs your script multiple times (typically once for each day of a month) and creates a calendar with reminders filled into the appropriate calendar boxes.

    This will create a niceASCII (or UTF-8) calendar in your terminal. We’ll see in Chapter 12 how you can use different options, along with some helper programs, to create PDF, PostScript and HTML calendars.

3.  **Purge Mode** is used to remove reminders from your script if they have expired. Purge Mode will not be covered in this book, because it’s not essential to use it and it is very well documented in the **remind**(1) man page.

4.  **Server Mode** is a special mode used by the TkRemind graphical front-end for Remind. Again, I won’t cover it in this book because it is very well documented in the **tkremind**(1) man page. There is a slight variant called **Daemon Mode** that is covered in Chapter 17.

#### 2.2.1 Some Remind Command-Line Options

Remind has *many* command-line options; I won’t document them all in this book. Instead, see the **remind**(1) man page. The following list shows some ways to run Remind. They all assume that *pathname.rem* contains the following, and that Remind is being run on January 2nd, 2026.

    # Example reminder script for command-line invocations that follow
    REM Wednesday MSG Swimming
    REM 15 January 2026 MSG Meeting
    REM 20 January MSG Jane's Birthday

And here are some ways to run Remind:

- `$ remind pathname.rem` – this is the normal way to run Remind in Agenda Mode.

- `$ remind -c pathname.rem` – this runs Remind in Calendar Mode and produces a nice ASCII calendar in your terminal. The calendar will look something like this:

      +----------------------------------------------------------------------------+
      |                                January 2026                                |
      +----------+----------+----------+----------+----------+----------+----------+
      |  Sunday  |  Monday  | Tuesday  |Wednesday | Thursday |  Friday  | Saturday |
      +----------+----------+----------+----------+----------+----------+----------+
      |          |          |          |          |1         |2  ******* |3        |
      |          |          |          |          |          |          |          |
      +----------+----------+----------+----------+----------+----------+----------+
      |4         |5         |6         |7         |8         |9         |10        |
      |          |          |          |Swimming  |          |          |          |
      +----------+----------+----------+----------+----------+----------+----------+
      |11        |12        |13        |14        |15        |16        |17        |
      |          |          |          |Swimming  |Meeting   |          |          |
      +----------+----------+----------+----------+----------+----------+----------+
      |18        |19        |20        |21        |22        |23        |24        |
      |          |          |Jane's    |Swimming  |          |          |          |
      |          |          |Birthday  |          |          |          |          |
      +----------+----------+----------+----------+----------+----------+----------+
      |25        |26        |27        |28        |29        |30        |31        |
      |          |          |          |Swimming  |          |          |          |
      +----------+----------+----------+----------+----------+----------+----------+

  If you are running a terminal capable of displaying UTF-8 characters, you can use this variant instead: `$ remind -cu pathname.rem` which produces solid lines instead of fake lines composed of `+`, `-` and `|` characters. The output will look something like this:

      ┌────────────────────────────────────────────────────────────────────────────┐
      │                                January 2026                                │
      ├──────────┬──────────┬──────────┬──────────┬──────────┬──────────┬──────────┤
      │  Sunday  │  Monday  │ Tuesday  │Wednesday │ Thursday │  Friday  │ Saturday │
      ├──────────┼──────────┼──────────┼──────────┼──────────┼──────────┼──────────┤
      │          │          │          │          │1         │2  ******* │3        │
      │          │          │          │          │          │          │          │
      ├──────────┼──────────┼──────────┼──────────┼──────────┼──────────┼──────────┤
      │4         │5         │6         │7         │8         │9         │10        │
      │          │          │          │Swimming  │          │          │          │
      ├──────────┼──────────┼──────────┼──────────┼──────────┼──────────┼──────────┤
      │11        │12        │13        │14        │15        │16        │17        │
      │          │          │          │Swimming  │Meeting   │          │          │
      ├──────────┼──────────┼──────────┼──────────┼──────────┼──────────┼──────────┤
      │18        │19        │20        │21        │22        │23        │24        │
      │          │          │Jane's    │Swimming  │          │          │          │
      │          │          │Birthday  │          │          │          │          │
      ├──────────┼──────────┼──────────┼──────────┼──────────┼──────────┼──────────┤
      │25        │26        │27        │28        │29        │30        │31        │
      │          │          │          │Swimming  │          │          │          │
      └──────────┴──────────┴──────────┴──────────┴──────────┴──────────┴──────────┘

- `$ remind -s pathname.rem` – runs Remind in Calendar Mode, but produces “simple output” suitable for reading by both a human and a machine. It can be a quick way to check the output of <sup>2</sup> your reminders in Calendar Mode. The output will look something like this:

      2026/01/07 *   * Swimming
      2026/01/14 *   * Swimming
      2026/01/15 *   * Meeting
      2026/01/20 *   * Jane's Birthday
      2026/01/21 *   * Swimming
      2026/01/28 *   * Swimming

  (The asterisks have to do with an interchange format for sending calendar data to other programs; you can ignore them for now. The details are described in the **rem2ps**(1) man page.)

- `$ remind -ppp pathname.rem` – runs Remind in Calendar Mode, but produces JSON output designed for machine consumption. Remind ships with various helper programs that ingest this JSON and produce PDF and HTML calendars. Because the JSON output is not meant for human consumption, I won’t show it here. But you can easily run Remind to generate it yourself if you want to see what it looks like.

- `$ remind -n pathname.rem` – runs Remind in a variant of Agenda Mode called *Next Mode*. In this mode, the *next* trigger date of each `REM` command is printed in a format similar to the Simple Calendar format. The output for our example will look like this:

      2026/01/07 Swimming
      2026/01/15 Meeting
      2026/01/20 Jane's Birthday

  These are the *next* dates that each `REM` command will trigger as calculated on January 2nd, 2026.

If you supply the single character `-` instead of a pathname, Remind reads commands from standard input. This lets you type commands interactively. If Remind was compiled against the readline library, then in interactive mode it will have bash-style command-line editing.

## 2.3 The REM Command: An Introduction

You’ve already seen examples of the `REM` command. In its simplest form, a `REM` command looks like this:

    REM trigger-spec MSG body

> <sup>2</sup> Yes, I know the dates are printed using the format YYYY/MM/DD instead of YYYY-MM-DD. This is an accident of history and hasn’t been changed so as not to break backward compatibility,

A *trigger-spec* tells Remind when to *trigger* the reminder. A basic trigger-spec contains the following parts:

- A *year*. This is a number from 1990 to 5990. A trigger-spec may contain zero or one *year* parts. Remind cannot handle years before 1990; that is because internally, it represents dates as a count of days since 1 January 1990. The date 1990-01-01 is Remind’s *beginning of time*.
- A *month*. This is an English month name such as `February` or `June`, or an abbreviation of three letters or more such as `Apr` or `Sept`. A trigger-spec may contain zero or one *month* parts.
- A *day*. This is a number from 1 to 31 that represents a day number within a month. A trigger-spec may contain zero or one *day* parts.
- A *weekday list*. This is a space-separated list of English weekday names like `Sunday` or abbreviations of at least three letters like `Fri` or `Thur`. A trigger-spec may contain zero or one *weekday lists*.

A trigger-spec may be *satisfied* on one or more dates. Any time a date matches whichever components of a trigger-spec are present, then the date satisfies the trigger-spec. If a trigger-spec is satisfied on a particular date, then the reminder will be *triggered* on that date. The closest such date on or after today is called the *trigger date*. Here are some examples of `REM` commands:

    REM MSG This will trigger every day.
    REM 1 MSG This will trigger on the 1st of every month.
    REM Apr MSG This will trigger every day in April, in any year.
    REM 2025 MSG This will trigger every day in 2025.
    REM 3 Sep MSG This will trigger on September 3rd, every year.
    REM 15 2025 MSG This will trigger on the 15th of every month in 2025.
    REM July 2026 MSG This will trigger every day in July 2026.
    REM 10 October 2027 MSG This will trigger only on October 10th, 2027.

The eight commands above do not include weekday lists. The behavior of a weekday list depends on whether or not the trigger-spec has a *day* component. Here are trigger-specs without a day component:

    REM Sat Sun MSG Triggered every Saturday and Sunday.
    REM Wed June MSG Triggered every Wednesday in June, any year.
    REM Thu 2026 MSG Triggered every Thursday in 2026.
    REM Tue Thu Apr 2026 MSG Every Tuesday and Thursday in April 2026.

If the trigger-spec has *both* a day *and* a weekday component, then the behavior changes: The reminder is triggered on the first day *on or after the day* that is *also* found in the weekday list. It’s probably easiest to look at examples to understand:

    REM 1 Sat MSG First Saturday of every month.
    REM 8 June Sat Sun MSG The first day after 8 June that is a Sat or Sun.
    REM Mon 8 2026 MSG The second Monday of every month in 2026.
    REM Thu Fri 20 Aug 2025 MSG Only August 21st, 2025.

Let’s explain these last four:

- In the first reminder, the trigger date will be the first Saturday that occurs on or after the 1st of every month.
- In the second reminder, the trigger date will be the first day on or after 8 June that is a Saturday or a Sunday. In 2025, June 8th is a Monday, so the trigger date will be the following Saturday, June 13th 2025. Note that the reminder will *not* trigger on Sunday, June 14th 2025. As soon as *any* weekday constraint is satisfied, then that is the *only* one that is used. In 2031, June 8th is a Sunday, so in that year, the trigger date will also be June 8th, satisfying the `Sun` weekday constraint.
- In the third reminder, the trigger date will be the first Monday on or after the 8th of every month in 2026. This happens to be the second Monday of every month in 2026; convince yourself of that!
- In the fourth reminder, 20 Aug 2025 is a Wednesday. The first day on of after that date that is in the weekday list is Thursday, 21 Aug 2025 and that is the only trigger date.

Generally speaking, Remind is pretty relaxed about the order of trigger components. The `REM` commands within each of the following groups are equivalent to one another. Additionally, if all three day, month, and year components are present, you can simply write *YYYY-MM-DD*:

    REM January 1 MSG New Year's Day
    REM 1 January MSG New Year's Day

    REM 25 March 2025 MSG Concert
    REM 2025 March 25 MSG Concert
    REM March 25 2025 MSG Concert
    REM 2025-03-25 MSG Concert

    REM Mon 5 Feb MSG Appointment
    REM 5 Mon Feb MSG Appointment
    REM Feb 5 Mon MSG Appointment

## 2.4 The Remind Trigger-Calculation Algorithm

This is the most important section in this book. Make sure you understand the Remind trigger-calculation algorithm. If you do, you will have much success writing Remind scripts. If you do not, you will be eternally mystified.

When Remind executes a `REM` command, here’s what it does internally.

1.  Set a variable *X* to today’s date.
2.  Look at the trigger-spec and determine whether or not *X* satisfies the trigger-spec.
3.  If *X* does indeed satisfy the trigger-spec, then *X* is returned as the trigger date.
4.  Otherwise, add one day to *X* and go back to step 2.

Of course, Remind does not *actually* work that way. Consider the following `REM` command:

    REM 14 September 2003 MSG Wow.

If we ran Remind on 20 Aug 2025, the algorithm above would never end because Remind would keep checking subsequent days in a fruitless attempt to find something that satisfies the trigger-spec.

So the actual algorithm is modified in two ways: (1) It terminates if it can convince itself that *no* future date will ever satisfy the trigger spec, and (2) it incorporates many optimizations that eliminate the need to actually check every single day starting from today and stretching out into the future. However:

**Remind** ***behaves*** **as if it uses the algorithm described previously.**

## 2.5 Advance Warning

Let’s say you’ve set up a bunch of reminders to remind you about friends’birthdays. For example, suppose you have this:

    REM 16 July MSG Jane's birthday.

You dutifully run Remind every day when you log in to your computer, and on 15 July, the output of Remind is:

    No reminders.

But then on 16 July, you’re confronted with:

    Jane's birthday.

Oh no! You would have liked to have had some heads-up to go and buy Jane a card. As it is, you have to scramble to get the card in time. It sure would have been nice if Remind had a way to give you a little bit of advance notice for an upcoming event...

Well, there is a way. You can add a *delta* to the trigger spec. A delta is a number prefixed by two plus <sup>3</sup> signs —for example, `++10`.

This causes Remind to trigger a reminder *not only* on the actual computed trigger date, *but also* on the delta days prior to the actual trigger date. So if we modified the example to look like this:

    REM 16 July ++10 MSG Jane's birthday.

Remind would start warning you of Jane’s birthday on 6 July, and would issue the reminder every day through 16 July.

But there’s a problem. If you run Remind on, say, 8 July, it will print:

    Jane's birthday.

But Jane’s birthday isn’t on 8 July. It’s on 16 July. How can we get Remind to give us more information about exactly when a reminder’s trigger date is?

The answer is the *substitution filter*.

## 2.6 The Substitution Filter

Before Remind prints the body of a reminder, it runs it through a text filter called the *substitution filter*. This filter replaces certain sequences of characters that begin with a percent sign `%` with different information. The substitution filter is covered in gory detail in the **remind**(1) man page, so I’ll just mention some of the more popular sequences.

Let’s change our `REM` command to look like this:

    REM 16 July ++10 MSG Jane's birthday is %b.

If we run Remind on 6 July, we get this:

    Jane's birthday is in 10 days' time.

If we run it on 15 July, we get this:

    Jane's birthday is tomorrow.

and if we run it on 16 July:

    Jane's birthday is today.

> <sup>3</sup> There’s another form of delta that has *one* plus sign that will be explained in Section 3.4 on page 24.

#### 2.6.1 Some Substitution Sequences

As I wrote earlier, the substitution filter recognizes many sequences. I’ll list some of the most popular here. For the exhaustive list, see the **remind**(1) man page.

`%a` Replaced with “on *weekday*, *day month*, *year*”. For example, a reminder whose trigger date is 2025- 09-14 would yield “on Sunday, 14 September, 2025”

`%b` Replaced with “in *n* days’ time”, “tomorrow” or “today”, depending on the relationship between the trigger date and today’s date.

`%c` Replaced with “on *weekday*”.

`%_` Replaced with a newline. Normally, Remind *removes* newlines in the body of the reminder (this is the fate of the newlines embedded in continued lines.) **%\_** lets you explicitly put a newline in a reminder.

`%%` Replaced with a literal percent sign, **%**.

#### 2.6.2 Limiting the Text in Calendar Mode

The special substitution sequence `%"` is used to limit what appears in Calendar Mode. For example, suppose you have the following reminder:

    REM 20 January +8 MSG Bob's birthday is %b

In Agenda Mode on 20 January, that will result in: `Bob's birthday is today`. However, in Calendar Mode, the text “is today” also uselessly appears in the calendar box, when all you really need is “Bob’s birthday”.

You can fix it as follows:

    REM 20 January +8 MSG %"Bob's birthday%" is %b

In Agenda Mode, the `%"` sequences are *completely ignored*. In Calendar Mode, however, if they appear, then *only* the text between the two `%"` sequences is put into the calendar.

## 2.7 The Banner

You may have noticed that in Agenda Mode, if there are reminders, Remind prints a banner similar to this:

    Reminders for Monday, 2nd February, 2026 (today):

The banner may be changed with the `BANNER` command, which looks like this:

    BANNER header-text

The *header-text* can be anything you want; before issuing the banner, Remind passes *header-text* through the substitution filter, with the effective date as the trigger date. The default `BANNER` text is equivalent to:

    BANNER Reminders for %w, %d%s %m, %y%o:

Consult the **remind**(1) man page for information about these substitution sequences. If you don’t want any banner at all, you can put this at the top of your reminder script:

    BANNER %

## 2.8 Counting Backwards

So far, we’ve seen how to write reminders for the first, second, third and fourth Monday (for example) of a month. But how do we write a reminder for the *last* Monday of a month? Or the last day? Months have different lengths; some have four Mondays and some have five.

<sup>4</sup> The solution is to count backwards using a *back*, which is a number preceded by two minus signs, like this: `--``n`

If you want a reminder on the last day of every month, for example, write it like this:

    REM 1 --1 MSG Last day of the month

The way Remind calculates the trigger date is as follows: It calculates what the trigger date would be without the back, and then it subtracts the number of days indicated by the back. Since a reminder of `REM 1` is simply the first day of every month, subtracting 1 gives the last day of the previous month. This reminder therefore triggers on the last day of every month.

How about if you want the last Friday of every month? That’s simply the first Friday of the following month and then go back by 7 days, like this:

    REM Friday 1 --7 MSG Last Friday of the month

Similarly, this gives you the last Tuesday in February:

    REM Tue 1 March --7 MSG Last Tuesday of February

Note that in the previous example, even though we want the last Tuesday of February, we specify the month as March because we are going backwards from there.

> <sup>4</sup> As you may have guessed, there’s another form of *back* that uses only one minus sign and that will be explained in Section 3.4 on page 24.

## 2.9 Some Syntactic Sugar

Remind has syntactic sugar for some common types of reminders. For example, although you can write the following reminders (convince yourself that they’re correct):

    REM Mon 1 MSG First Monday of every month
    REM Tue 8 May MSG Second Tuesday in May
    REM Fri 15 MSG Third Friday of every month
    REM Sat 22 June 2026 MSG Fourth Saturday in June 2026

Remind lets you write them as follows:

    REM First Monday MSG First Monday of every month
    REM Second Tuesday in May MSG Second Tuesday in May
    REM Third Friday MSG Third Friday of every month
    REM Fourth Saturday in June 2026 MSG Fourth Saturday in June 2026

The word “in” is ignored, but allowed in order to make the reminders more readable.

You might ask why there’s no syntactic sugar for:

    REM Fifth Thursday MSG Fifth Thursday of every month

The reason is that while there are four of every weekday in every month, not all weekdays appear five times in a month and so more complicated mechanisms are needed for the “fifth Thursday” reminder, which we will discover in Section 7.4.1 on page 61.

Another piece of syntactic sugar simplifies writing reminders for “the last *something* of a month”. The reminders within each of the following groups are equivalent to others within the group. Note that the character `~` in the second reminder of each pair is a tilde, not a minus-sign.

    REM 1 --1 MSG The last day of every month
    REM ~~1 MSG The last day of every month

    REM Fri 1 --7 MSG The last Friday of every month
    REM Fri ~~7 MSG The last Friday of every month

    REM 1 Mar --1 MSG The last day of February
    REM Feb ~~1 MSG The last day of February

    REM Fri 1 Jan 2027 --7 MSG The last Friday in 2026
    REM Fri Dec 2026 ~~7 MSG The last Friday in 2026

Note that in the last examples, the `~~1` automatically corrects the month and year for the one you *want* rather than the one you’re moving back from.

You cannot use a *day* component together with a `~~``n` component because the latter has an implied day component. In fact, `~~``n` is *exactly* the same as `1 --``n` except for the potential adjustment of month and year mentioned previously.

<sup>5</sup> One last piece of syntactic sugar is based on the previous syntactic sugar . The following sets of reminders are equivalent:

    REM ~~1 MSG The last day of every month
    REM Lastday MSG The last day of every month

    REM June ~~1 MSG The last day of every June
    REM June Lastday MSG The last day of every June

    REM Monday May ~~7 MSG The last Monday in May
    REM Last Monday May MSG The last Monday in May
    REM Last Monday in May MSG The last Monday in May

## 2.10 Checking What Will Happen on a Specific Date

Normally, when you run a Remind script from the command line like this:

    $ remind filename

then today’s date is taken from your computer’s internal clock and trigger dates are calculated on the basis that today is... well... *today*. But what if you want to see how Remind will behave on some other date? You can simply supply a date on the command line after the *filename*, in one of two ways. Consider these examples:

    $ remind filename 14 June 2033
    $ remind filename 2033-06-14

Both of those commands run the Remind script *filename*, but they pretend that today is 14 June, 2033. This lets you see how the script will behave on the given date.

## 2.11 The “Current” Date and Time

Remind’s idea of the current date and time are not as simple as the clock time as reported by the operating system. Remind’s ideas of the current date and time are called the *effective date* and *effective time*, and here’s how they are defined.

> <sup>5</sup> So perhaps it is syntactic icing sugar?

- In Agenda Mode:

  **–** If you run Remind without supplying a date or time on the command line, then the effective date and time are the clock date and time returned by the operating system, in the local time zone. (That is, exactly what you see when you type the command `date`).

  **–** If you supply a date, but not a time, on the command line, then the effective date is set to the date you supply on the command line, and the effective time is set to the clock time as returned by the operating system.

  **–** If you supply a date and a time on the command line, then the effective date is set to the date you supply on the command line, and the effective time is set to the time you supply on the command-line.

- In Calendar Mode, the effective date is set to the date of each calendar box as Remind runs through the days of the calendar, and the effective time is set to midnight (`00:00`).

I will also sometimes refer to *system date* and *system time*. These always refer to the clock date and time returned by the operating system, in the local time zone. And if I refer to *today* or *now*, those refer to the *effective date* and *effective time*, respectively.

## 2.12 Running Remind Multiple Times in a Row

You can run Remind multiple times in a row by adding a command-line parameter of the form `*``n`, where *n* is a positive integer, to the end of the command-line. You should protect it from shell expansion by enclosing it in single quotes. This causes Remind to run *n* times in Agenda Mode, with the effective date incremented by one day for each subsequent run. Here is an example:

    # Run Remind 5 times, starting on 2026-04-05 and running through 2026-04-09
    $ remind file.rem 2026-04-05 '*5'

You don’t need to supply a date on the command line; if you don’t, then the `*``n` repetitions start from the actual system date.
