---
title: "Appendix B: Calendar Systems"
rules:
  - name: DateOutsideRepresentableRange
    description: >-
      Any date outside 1990-01-01 … 5990 in a trigger or a constant. Remind counts days from
      1990-01-01, so the floor is structural rather than a policy. Collecting the check in one
      rule keeps the message consistent wherever the date was written.
---

# Appendix B: Calendar Systems

This Appendix is a brief discussion of calendar systems. You don’t need to read it to use Remind, but I hope you find it interesting anyway!

Ultimately, our calendars are derived from the motion of objects in the Solar System. The most obvious consequence of planetary motion is our cycle of day and night, caused by the rotation of the Earth around its axis. The time it takes for one full rotation of the Earth with respect to the Sun is called a *solar day* and is the time between two consecutive appearances of the Sun at its highest point in the sky. A solar day does not have a fixed length because the Earth moves in an eccentric orbit around the Sun and spins on an inclined axis. What we think of as a 24-hour period is a *mean solar day* which is the average length of a solar day over a long period of time.

The next most obvious effect of astronomical body motion that we observe is the phase of the Moon. The average time between new moons is called a *synodic month* and was described in detail in Section 11.3 on page 81.

The final cyclical astronomical phenomenon that affects the calendar is the time between two summer solstices (or winter solstices). This is called a *tropical year*.

Now, it would be nice if a solar day, a synodic month, and a tropical year were all related by integer multiples of each other, or at least by simple fractional multiples, but the odds against this happening are... well... astronomical. It turns out that a mean synodic month is approximately 29.530589 mean solar days, and a tropical year is approximately 365.24217 mean solar days or 12.3683 mean synodic months.

## B.1 Reconciling Days, Months and Years

It would be very annoying to have months that are 29.530589 days long and years that are 365.24217 days long, since the month and the year would change partway through the day and at varying times of the day. So most calendar systems have months and years that comprise an integer number of days, and they make integer-sized adjustments to try to compensate for the irrational ratios between years, months and days.

There are three basic approaches most calendar systems take:

1.  Try to make months closely correspond to synodic months, and don’t care about aligning with the tropical year.

    This is the approach taken by the Islamic calendar, whose average year length is about 354.367 days. As such, the calendar regresses through the seasons every 33 tropical years or so.

2.  Try to make months closely correspond to synodic months, and years to closely correspond with the tropical year. This is the approach taken by the Hebrew and Chinese calendars; they are called *lunisolar calendars* and are based on the Metonic cycle described in Section 11.3 on page 81.

    Unfortunately, the Metonic cycle of 235 synodic months isn’t *exactly* equal to 19 tropical years, so lunisolar calendars also show a slight drift with respect to the tropical year. For example, the Hebrew calendar drifts by about one day every 216 years.

3.  Try to make years correspond closely to the tropical year and don’t worry about lining up months with synodic months. This was the approach taken by the Julian Calendar, and is the approach used by the Gregorian Calendar, which is the common civil calendar in most parts of the world and is what most people simply think of as “the calendar”.

    The Gregorian year is normally 365 days long. However, every so often, a day is added to the year (February 29th) making it 366 days long; such a year is called a *leap year*. The Gregorian rules for determining a leap year are as follows:

    - If the year is a multiple of 400, then it is a leap year.
    - Otherwise, if the year is a multiple of 100, then it is *not* a leap year.
    - Otherwise, if the year is a multiple of 4, then it is a leap year.
    - Otherwise, it is not a leap year.

These rules result in a 400-year cycle of 146 097 days for an average year length of 365.2425 days. This is pretty close to the tropical year length of 365.24217 days... but it’s not exact. Even the Gregorian calendar drifts by about one day every 3030 years or so.

To make matters worse, the rotation of the Earth is slowing down because some of the Earth’s angular momentum is being transferred to the Moon via tidal interactions. The rate of deceleration is tiny (currently about 1.8 milliseconds per century) but over very long periods of time, it will make the day meaningfully longer and thus the tropical year will contain fewer mean solar days.

## B.2 Year Numbering

The year number in a calendar (for example, as I write this, it is 2026 according to the Gregorian calendar and 5786 according to the Hebrew calendar) has to be related to some event in the past. The Gregorian year is supposed to be related to the birth of Jesus Christ, which to the eternal annoyance of computer scientists is denoted by the year 1 rather than the year 0.

The numbering of Hebrew years is supposed to start with the creation of the Universe, also presumably in year 1. This is quite likely to be inaccurate to the tune of 13.8 billion years or so.

But really, it doesn’t matter what the reference point is for year numbering, as long as everyone who uses a given calendar system agrees on the year number.

## B.3 Calendar Systems supported by Remind

Remind supports the Gregorian calendar as its main calendar system, and the Hebrew calendar as a secondary system. Remind’s algorithms should be good enough for the next few hundred years, but if you are reading this book in the far distant future relative to 2026, feel free to submit patches if the calendar has been reformed.
