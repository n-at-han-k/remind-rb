---
title: "Chapter 16: Time Zones"
rules:
  - name: TimeZoneWithoutAt
    description: >-
      A TZ keyword on a reminder with no AT clause. The book states it as a requirement: a bare
      date cannot be converted between zones, so TZ without AT is meaningless. Cheap, exact, and
      the kind of thing that only shows up months later when the reminder fires on the wrong
      day.
  - name: UnknownTimeZoneName
    description: >-
      A time-zone name that does not resolve under /usr/share/zoneinfo. Remind warns but cannot
      truly validate, and an unrecognised name gives undefined results rather than an error.
      Names are case-sensitive, so `america/toronto` is a real and easy mistake.
  - name: TimeZoneNameCaseOnlyMismatch
    description: >-
      A zone name that matches a real one except in case. Turns the warning above into an
      actionable message: it can name the intended zone rather than just doubting the one
      written.
  - name: SatisfyEvaluatedInForeignZone
    description: >-
      A SATISFY expression on a REM that also carries TZ. The expression sees the date in the TZ
      zone, not the local one, and the conversion back happens only after the trigger is final.
      Correct, documented, and reliably surprising — worth an informational note rather than a
      fix.
---

# Chapter 16: Time Zones

So far, all the reminders and date-manipulation functions you’ve seen have assumed that the date and time is in the *local time zone*—that is, the time zone that is configured as your computer’s time zone.

Remind has facilities for converting dates and times between different time zones and also for specifying reminders in different time zones. Note that all time zone conversions are done by your system’s C library, so the accuracy of conversions depends on how good your C library’s time zone implementation is.

## 16.1 Reminders in a Specific Time Zone

If you want to issue a reminder based on a date a time in a time zone other than your computer’s default time zone, use the `TZ` keyword in the `REM` command. The syntax looks like this:

    REM trigger TZ timezone MSG body

The format of *timezone* is system-specific, but on most UNIX systems, it will be something like `America/Toronto` or `Australia/Sydney`. Note that time zone names *are* case-sensitive.

On most UNIX-like systems, time zone data is stored under the directory `/usr/share/zoneinfo` and the name of a time zone is simply the relative path to the time zone information under that directory.

If your system contains the file `/usr/share/zoneinfo/zonenow.tab`, then you can get a list of some of the valid time zone names supported by your system with this shell command:

    $ awk 'print $3' /usr/share/zoneinfo/zonenow.tab | grep / | sort

**Note:** If you use the `TZ` keyword, then you *must also* use the `AT` keyword to specify a time. Non-timed reminders do not permit a time zone specification because it’s impossible to convert just a date from one time zone to another; you need a time as well.

As an example, suppose I have a friend in Sydney, Australia, whom I want to call at 22:00 Sydney time every Thursday. Consider this reminder script:

    REM Thursday AT 22:00 TZ Australia/Sydney MSG Call Sue

My time zone is `America/Toronto`, so if I run the above script as follows:

    $ remind -s2 aus.rem 1 mar 2026

The output is:

    2026/03/05 * * * 360 6:00am Call Sue
    2026/03/12 * * * 420 7:00am Call Sue
    2026/03/19 * * * 420 7:00am Call Sue
    2026/03/26 * * * 420 7:00am Call Sue
    2026/04/02 * * * 420 7:00am Call Sue
    2026/04/09 * * * 480 8:00am Call Sue
    2026/04/16 * * * 480 8:00am Call Sue
    2026/04/23 * * * 480 8:00am Call Sue
    2026/04/30 * * * 480 8:00am Call Sue

A few things to note:

- On 2026-03-05, Sydney is 16 hours ahead of America/Toronto and the reminder is issued for 06:00 in my time zone.
- The reminders for 2026-03-12 through 2026-04-02 take place when America/Toronto has started Daylight Saving Time, and Sydney is also still on Daylight Saving Time. In this situation, Sydney is 15 hours ahead of America/Toronto and so the reminder is issued at 07:00.
- The reminders for 2026-04-09 through 2026-04-30 take place after Sydney has switched back to standard time. It is therefore 14 hours ahead of America/Toronto and the reminder is issued at 08:00.

#### 16.1.1 How TZ works

When Remind evaluates a `REM` command with a `TZ` clause, it effectively performs the following actions:

- It changes the system time zone to the specified time zone. It also adjusts the effective date and time to be in the new time zone.
- It evaluates the `REM` command as usual. Note that any `SATISFY` expressions are evaluated in the time zone specified by `TZ`
- Once a trigger date and time have been calculated, they are converted back to the local date and time and the system time zone is switched back to the local time zone.

An example is probably best to illustrate this. Suppose I want a reminder at 01:00 every Friday the 13th in the Universal Time Zone. I could use this:

    REM 13 TZ Universal AT 1:00 SATISFY [$Tw == 5] MSG Booo!

I live in the America/Toronto time zone, which as of February 2026 is 5 hours behind Universal Time. If I run the above script as follows:

    $ remind -n boo.rem 1 Feb 2026

The output is:

    2026/02/12 8:00pm Booo!

Note that the final calculated trigger date and time is 2026-02-12 at 20:00 (in the America/Toronto time zone.) This is a Thursday evening. But in the Universal time zone, it works out to 2026-03-13 at 01:00, just what we wanted. When the `SATISFY` expression is evaluated, it sees the date *in the Universal time zone*. Conversion back to the local time zone is done only *after* the final trigger date/time have been calculated.

## 16.2 Time Zone Conversion Functions

Remind has a few built-in functions for converting between time zones:

- `utctolocal(``dt``)` – Given a DATETIME object *dt* interpreted in UTC (Coordinated Universal Time), return a DATETIME object representing the same time, but in the local time zone.
- `localtoutc(``dt``)` – Given a DATETIME object *dt* interpreted in the local time zone, return a DATETIME object representing the same time, but in UTC.
- `tzconvert(``dt``, srczone [, dstzone``)` – Given a DATETIME object *dt* and a STRING *srczone*, convert *dt* from the time zone named by *srczone* to the time zone named by the STRING *dstzone*. If *srczone* is the empty string, the local time zone is used. If *dstzone* is omitted or is the empty string, the local time zone is used.

Here are some examples of the functions in action. The following examples assume that the local time zone is “America/Toronto”.

    SET a localtoutc('2025-01-20@14:44')        (a is set to '2025-01-20@19:44')
    SET a utctolocal('2031-01-01@00:00')        (a is set to '2030-12-31@19:00')

    # a is set to 2027-03-04@05:00
    SET a tzconvert('2027-03-04@09:30', "America/St_Johns", "America/Los_Angeles")

As the last example shows, “America/St_Johns” is 4 hours and 30 minutes ahead of “America/Los_Angeles”

## 16.3 Validating Time Zone Names

Unfortunately, the standard Linux library functions for manipulating time zones have no way to validate that a time zone name is actually correct. If you supply an incorrect time zone name, Remind will give undefined results.

Remind does try to validate time zone names by looking at files under `/usr/share/zoneinfo` and will issue a warning if the specified time zone doesn’t appear to exist

However, there are ways to specify time zones other than by using file names under `/usr/share/zoneinfo`. For example, under Linux you can use any of the formats documented in the glibc manual.

If you happen to use a time zone name that you know is correct, but Remind issues a warning, simply prefix the time zone name with a `!` to suppress the warning.

For example: Under Linux, you can specify time zones that are *n* hours West of UTC as `UTC+``n` and ones <sup>1</sup> that are *n* hours East of UTC as `UTC-``n`.

If you do something like this:

    # a is set to 2026-06-01@17:00 but with warnings
    set a tzconvert('2026-06-01@10:00', "UTC+6", "UTC-1")

Remind will issue warnings about the time zone names. To suppress the warnings, use:

    # a is set to 2026-06-01@17:00
    set a tzconvert('2026-06-01@10:00', "!UTC+6", "!UTC-1")

> <sup>1</sup> I know those signs relative to UTC look backwards, but that’s the specification.
