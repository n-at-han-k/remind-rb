---
title: "Chapter 11: Astronomical Events"
rules:
  - name: LatitudeLongitudeNotString
    description: >-
      $Latitude or $Longitude set to something other than a float-shaped STRING. Remind has no
      floating-point type, so the coordinate has to arrive as a string — `SET $Latitude 45.42`
      is not a near miss, it is a different thing entirely. Out-of-range values silently produce
      nonsense sunrise times.
  - name: AstronomyWithoutLocation
    description: >-
      Sun or Moon functions used in a file tree that never sets $Latitude and $Longitude. Remind
      falls back to its shipped default — Ottawa City Hall — and reports confidently wrong times
      for everybody else.
  - name: MoonPhaseArgumentRange
    description: >-
      A phase or event selector outside the range its function accepts. The four-phase and four-
      event encodings are small closed sets, so a literal 4 is always a bug and always visible
      without running the script.
  - name: EasterdateFromToday
    description: >-
      easterdate()/orthodoxeaster() called on today() inside a trigger that adds an offset. The
      book spells out the failure: with the date form, on Easter Monday the function returns
      *next* year's Easter, so the +1 reminder never triggers. Passing the year avoids it.
  - name: MoonriseDatePartUnchecked
    description: >-
      moonrise()/moonset() result used as a trigger without checking its date part. Not every
      day has a moonrise, so the returned date may not be the date asked for — the guard in the
      book's example is the difference between a moonrise calendar and a subtly shifted one.
---

# Chapter 11: Astronomical Events

Remind has built-in functions for calculating the dates and times of various events like solstices, equinoxes, Moon phases, sunrise and sunset. This chapter describes the astronomical functions.

## 11.1 Location

In order to correctly compute the times of astronomical events, Remind needs to know your location (latitude and longitude.) There are three system variables that specify your location. They are as follows:

- `$Latitude` – set this to a STRING that is a floating-point number representing your latitude in degrees, from -90 to 90. Positive latitudes are north of the Equator and negative latitudes are south of the Equator.

  Because Remind does not have a floating-point data type, you have to specify latitude as a STRING, but it must have the syntax of a floating-point number. For example, the default latitude that Remind ships with is the equivalent of:

      SET $Latitude "45.42055556"

- `$Longitude` – set this to a STRING that is a floating-point number representing your longitude in degrees, from -180 to 180. Positive longitudes are east of the Greenwich Meridian, and negative longitudes are west of the Meridian.

  As with latitude, you must specify longitude as a STRING, but it must have the syntax of a floating- point number. For example, the default longitude that Remind ships with is the equivalent of:

      SET $Longitude "-75.68944444"

  The default latitude and longitude happen to be the location of the City Hall in Ottawa, Ontario, Canada.

- `$Location` – this is optional, but is designed to hold the name of the locale where you are located. The default setting that Remind ships with is the equivalent of:

      SET $Location "Ottawa"

## 11.2 Sunrise and Sunset

The following built-in functions all take an optional DATE or DATETIME argument. They return a TIME. Note that if a DATETIME argument is supplied, only the date portion is used; the time portion is ignored. If no argument is supplied, then a default of `today()` is used.

- `sunrise([``x``])` – returns a TIME object which is the local time of sunrise. Sunrise is defined as the moment when the upper rim of the Sun appears on the horizon in the morning.

  Some places may not have a sunrise every day; if the Sun never sets on a specific day, then the INT `0` is returned. If it never rises on a specific day, then the INT `1440` is returned.

- `sunset([``x``])` – returns a TIME object which is the local time of sunset. Sunset is defined as the moment when the upper rim of the Sun disappears below the horizon in the evening.

  Some places may not have a sunset every day; if the Sun never sets on a specific day, then the INT `1440` is returned. If it never rises on a specific day, then the INT `0` is returned.

- `dawn([``x``])` – Similar to `sunrise()`, but returns the time when the center of the Sun is 6 degrees below the horizon in the morning. This is known as civil dawn.

- `dusk([``x``])` – Similar to `sunset()`, but returns the time when the center of the Sun is 6 degrees below the horizon in the evening. This is known as civil dusk.

- `ndawn([``x``])` – Similar to `sunrise()`, but returns the time when the center of the Sun is 12 degrees below the horizon in the morning. This is known as nautical dawn.

- `ndusk([``x``])` – Similar to `sunset()`, but returns the time when the center of the Sun is 12 degrees below the horizon in the evening. This is known as nautical dusk.

- `adawn([``x``])` – Similar to `sunrise()`, but returns the time when the center of the Sun is 18 degrees below the horizon in the morning. This is known as astronomical dawn.

- `adusk([``x``])` – Similar to `sunset()`, but returns the time when the center of the Sun is 18 degrees below the horizon in the evening. This is known as astronomical dusk.

Here are examples of how you can use the sun-related astronomical functions:

    REM NOQUEUE AT [sunrise()] MSG Sunrise %! %2.
    REM NOQUEUE AT [sunset()] MSG Sunset %! %2.
    # Similar patterns may be used for the other Sun-related functions

## 11.3 Moon-Related Functions

The period of the lunar phases is called a *synodic month*. This is how long the Moon takes to complete <sup>1</sup> one orbit around the Earth and averages about 29 days, 12 hours, 44 minutes and 3 seconds. However, because both the Moon’s and the Earth’s orbits are elliptical, a synodic month can vary by about seven hours from this mean.

It turns out that 235 mean synodic months is almost exactly 19 years long (it’s off by just over two hours) and several *lunisolar calendars* align their months to the moon phase but their years to the seasons by incorporating 7 leap months in a cycle of 19 years. This cycle of 235 mean synodic months is called the *Metonic cycle*.

Remind recognizes four Moon phases: The *New Moon* is when the Moon is completely dark (from Earth’s point of view), with the Moon, Earth and Sun aligned so the dark side faces Earth. The *Full Moon* is the opposite: The Moon is as illuminated as it can be, from Earth’s perspective, with the Moon, Earth and Sun aligned so the light side directly faces Earth.

The *First Quarter* is halfway between a New Moon and a Full Moon, when half of the Moon appears illuminated and it is heading towards a Full Moon. The *Last Quarter* is halfway between a Full Moon and a New Moon, when half of the Moon appears illuminated and it is heading towards a New Moon.

As an aside, we don’t get a lunar eclipse every Full Moon or a solar eclipse every New Moon because the Moon’s orbit is tilted by about 5 degrees with respect to Earth’s orbit around the Sun, and so eclipses can only happen when the two orbits are suitably aligned.

Remind has several functions related to phases and rising/setting of the Moon. They are as follows:

#### 11.3.1 Moon Phases

- `moonphase([``date [, time``]])` or `moonphase(``datetime``)` – This function returns the phase of the Moon on the given date and time, which default to `today()` and `now()`, respectively. The return value is an integer from 0 to 359, where 0 is a new Moon, 90 is the first quarter, 180 is a full Moon and 270 is the last quarter. You may supply the date and time as two separate arguments of type DATE and TIME, or one DATETIME object.
- `moondate(``phase [, date [, time``]])` or `moondate(``phase``, datetime``)` – given an integer *phase* from 0 to 3 where 0 is new Moon, 1 is first quarter, 2 is full Moon and 3 is last quarter, returns

> <sup>1</sup> Technically, both the Moon and the Earth orbit around their common center of gravity, However, since this point is some 1707 km below the surface of the Earth, effectively the Moon orbits the Earth.

the a DATE object holding the date on or after the given *date* and *time* (or *datetime*) on which the Moon is at the given phase. If *date* is omitted, it defaults to `today()`. If *time* is omitted, it defaults to `00:00`.

- `moontime(``phase [, date [, time``]])` or `moontime(``phase``, datetime``)` – takes the same argument as `moondate()` but returns a TIME object giving the exact time of day when the specific Moon phase is reached.
- `moondatetime(``phase [, date [, time``]])` or `moondatetime(``phase``, datetime``)` – takes the same argument as `moondate()` but returns a DATETIME object containing the date and time of day when the specific Moon phase is reached.

#### 11.3.2 Moonrise and Moonset

The following functions supply information about moonrise and moonset.

- `moonrise([``date``])` – This function returns a DATETIME giving the date and time of the first moonrise on or after `00:00` on *date*. If *date* is not supplied, it defaults to `today()`.

  Note that it is not uncommon for a day to have no moonrise, so the date part of the return value may not be the same as the *date* argument. If you want a calendar of moonrise times, you could use something like this:

      SET mr moonrise()
      IF datepart(mr) == today()
          REM NOQUEUE [mr] MSG Moon rises at %3.
      ELSE
          REM MSG No moonrise today
      ENDIF

- `moonset([``date``])` – This function returns a DATETIME giving the date and time of the first moonset on or after `00:00` on *date*. If *date* is not supplied, it defaults to `today()`.

  As with `moonrise`, there may not be a moonset on a given date, so the date part of the return value may differ from *date*.

- `moonrisedir([``date``])` – This function takes the same optional argument as `moonrise()` and returns an INT giving the compass direction of the first moonrise on or after `00:00` on *date*. The return value can range from `0` to `359`, where 0 is North, 90 is East, 180 is South and 270 is West.

- `moonsetdir([``date``])` – This function takes the same optional argument as `moonset()` and returns an INT giving the compass direction of the first moonset on or after `00:00` on *date*. The return value is interpreted as for `moonrisedir()`.

#### 11.3.3 Blue Moons

One of the definitions of a Blue Moon is that it is the second full moon in a calendar month. Here’s how you can use Remind to figure out when a blue moon is:

    REM SATISFY [$T == moondate(2, $T) && \
                 monnum($T) == monnum(moondate(2, $T-31))] \
        MSG Blue Moon!

The `SATISFY` condition is true if (1) today is a full moon, and (2) today’s calendar month is the same as the calendar month of the previous full moon.

In Ottawa, Ontario and local Ottawa time, there is a blue moon on 2026-05-31. The one after that is 2028-12-31. And the one after that is 2031-09-30.

## 11.4 Solstices and Equinoxes

A single function returns information about solstices and equinoxes:

- `soleq(``which [, start``])` – The integer argument *which* specifies which event we are interested in: 0 specifies the March Equinox, 1 the June Solstice, 2 the September Equinox and 3 the December Solstice.

  The optional *start* parameter can be an INT, in which case it specifies the year containing the event we’re interested in, or a DATE or DATETIME, in which case we’re looking for the first event on or after midnight on the specified date (or date part of the DATETIME.)

  The return value of `soleq()` is a DATETIME object giving the date and time of the specified solstice or equinox.

Here’s how you might use `soleq`:

    REM NOQUEUE [soleq(0)] March Equinox %! %3.
    REM NOQUEUE [soleq(1)] June Solstice %! %3.
    REM NOQUEUE [soleq(2)] September Equinox %! %3.
    REM NOQUEUE [soleq(3)] December Solstice %! %3.

## 11.5 Easter

<sup>2</sup> Although the date of Easter does not really correspond to an astronomical event , this seems like a good place to talk about it. Remind has two functions for calculating the date of Easter:

> <sup>2</sup> Easter used to be defined as the Sunday following the first Full Moon on or after the March equinox, but the rules for calculating Easter have since diverged from this definition

- `easterdate([``date``])` or `easterdate(``year``)` – If given an INT argument *year*, then returns a DATE object that is the date of Easter Sunday for the specified year. If given a DATE *date*, then returns the date of the next Easter Sunday on or after *date*. If no argument is supplied, then it defaults to `today()`.

  Note that `easterdate()` calculates the date of the Western Easter using an algorithm due to Donald Knuth.

  Here’s how you can use `easterdate()`:

      REM [easterdate($Uy) - 2] MSG Good Friday
      REM [easterdate($Uy)]     MSG Easter Sunday
      REM [easterdate($Uy) + 1] MSG Easter Monday

  Note that I used the INT-argument form of `easterdate()`. (The system variable `$Uy` is defined in Section 7.3 on page 60.) That is because the last reminder (Easter Monday) adds 1 to a calculated date and that runs the risk of breaking the Remind algorithm; if I supplied `today()` as the argument to `easterdate()`, then on Easter Monday the return value of `easterdate()` would be the *following* Easter Sunday, about a year into the future, and the reminder would never trigger.

- `orthodoxeaster([``date``])` or `orthodoxeaster(``year``)` – Takes the same arguments as `easterdate` and returns a DATE object containing the date of Easter Sunday, but computed according to the Eastern Orthodox rules rather than the Western rules.
