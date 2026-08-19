---
title: "Chapter 13: The Hebrew Calendar"
rules:
  - name: HebrewMonthName
    description: >-
      A Hebrew month name Remind does not recognise. A misspelling is a run-time error from
      hebdate, or, worse, a comparison against hebmon that is simply never true — the holiday
      quietly never appears. Note hebmon returns the canonical transliteration, so comparing
      against a non-canonical spelling fails even though hebdate would accept it.
  - name: HebrewDateOutOfRange
    description: >-
      A Hebrew day, month-length or year that cannot exist. `hebdate(30, "Elul", 5790)` is an
      `Invalid Hebrew date` error; Elul has 29 days. Fixed-length months make this decidable
      from literals.
  - name: HebrewDateNeedsLeftToRightMark
    description: >-
      ivritmon() pasted into a body with no left-to-right mark after it. Without the mark the
      numbers after the Hebrew month name print in the wrong order. It looks like a Remind bug
      and is a bidi one.
  - name: HebrewSunsetOffset
    description: >-
      Hebrew conversion of an evening date without the +1 adjustment. Remind rolls the Hebrew
      date at midnight, not sunset, so between sunset and midnight it is a day behind. Recording
      the idea here so the next reader does not re-derive it.
---

# Chapter 13: The Hebrew Calendar

In addition to support for the Gregorian calendar, Remind has built-in functions to support events based on the Hebrew calendar.

## 13.1 A Description of the Hebrew Calendar

The Hebrew calendar is a lunisolar calendar (Section 11.3 on page 81.) That means that its months are approximately aligned with phases of the Moon, while its years are approximately aligned with the solar year.

A normal Hebrew year has 12 months, alternately 30 and 29 days long. The Hebrew months are:

- Tishrey (ירשת), also spelled Tishri or Tishrei. 30 days long.
- Heshvan (ןוושח), also spelled Cheshvan or Kheshvan. 29 (or 30) days long.
- Kislev (ולסכ). 30 (or 29) days long.
- Tevet (תבט). 29 days long.
- Shvat (טבש), also spelled Shevat. 30 days long.
- Adar (רדא). 29 days long.
- Nisan (ןסינ). 30 days long.
- Iyar (רייא), also spelled Iyyar. 29 days long.
- Sivan (ןויס). 30 days long.
- Tamuz (זומת), also spelled Tammuz. 29 days long.
- Av (בא ). 30 days long.
- Elul (לולא). 29 days long.

(These months are given in the order used by the *civil year*. In Biblical times, Nisan was considered the first month and Tishrey was the 7th. This is the *ecclesiastical year*.)

In a cycle of 19 years, there are 7 leap years, being years 3, 6, 8, 11, 14, 17 and 19 of the cycle. In a leap year, an extra 30-day month is added before Adar. This extra 30-day month is called Adar A and the original 29-day Adar is called Adar B. This pattern ensures that a 19-year cycle has 235 months, in keeping with the Metonic Cycle.

Remind lets you use any of the following to name the two Adars in leap years:

- Adar A, Adar 1, Adar I, א רד א, א’ רד א, 1 רדא or רדאA
- Adar A, Adar 2, Adar II, ב רד א, ב’ רד א, 2 רדא or רדא B

The beginning of the year is 1 Tishrey and is referred to as *Rosh Hashanah* or *הנשה שא ר* (literally, “head of the year.”)

For certain religious reasons, Rosh Hashanah cannot occur on a Sunday, Wednesday or Friday. To adjust for this, a day is taken off Kislev or added to Heshvan. Thus, a regular year can have from 353 to 355 days, and a leap year can have from 383 to 385 days.

**Note:** Technically, the Hebrew date changes at sunset. However, Remind changes the date at midnight, not sunset. So in the period between sunset and midnight, Remind’s calculation of the Hebrew date will be a day earlier than the actual Hebrew date. This should not be much of a problem in practice, but you should keep it in mind and adjust if necessary.

## 13.2 Gregorian-to-Hebrew Conversion

The following functions simply convert a given Gregorian date to Hebrew date components. All of them take a single argument of type DATE, representing the Gregorian date. (Once again, if you are converting a date that is after sunset, you need to add 1 to the date argument to account for the fact that Hebrew dates change at sunset and not midnight.)

- `hebday(``date``)` – Returns an INT representing the day of the Hebrew month associated with the *date*.
- `hebmon(``date``)` – Returns a STRING containing the name of the Hebrew month associated with the *date*. This name is the transliterated name in ASCII characters (such as “Nisan” or “Kislev”) If a month has multiple accepted transliterations on input, `hebmon` always returns the “canonical” transliteration, which is the first one.

<sup>1</sup> • `ivritmon(``date``)` – Similar to `hebmon`, but returns the name of the month in UTF-8 Hebrew characters (such as “ןסינ”or “ולסכ”). For Adar A and Adar B, `ivritmon` returns ’אר דאand ’בר דא, respectively.

- `hebyear(``date``)` – Returns an INT representing the Hebrew year corresponding to *date*. Depending on the time of year, the Hebrew year is greater than the Gregorian year by either 3760 or 3761, with the increment taking place at Rosh Hashanah, which is in September or October.

Here is an example script:

    REM MSG Today is [hebday($T)] [hebmon($T)] [hebyear($T)]
    REM MSG Today is [hebday($T)] [ivritmon($T)] [hebyear($T)]

If we run that script on Tuesday, January 20th, 2026, the result is:

    Today is 2 Shvat 5786
    Today is 2 5786 טבש

The second example is a bit messed up because it really needs a left-to-right mark to reset the printing direction. You can fix it as follows:

    # Unicode character 0x200e is the LEFT-TO-RIGHT MARK
    SET LRM mbchar(0x200e)
    REM MSG Today is [hebday($T)] [ivritmon($T)][LRM] [hebyear($T)]

which yields:

    Today is 2 טבש  5786

The Unicode LEFT-TO-RIGHT MARK fixes up the formatting.

## 13.3 Hebrew-to-Gregorian Conversion

Hebrew-to-Gregorian conversion is handled by a single function called `hebdate`. This function may be called in a number of ways; I’ll document the most common ways here, but consult the **remind**(1) man page for a full description of how you can call `hebdate`.

> <sup>1</sup> “Ivrit” is the Hebrew word for Hebrew. (Technicallyתירבעis the Hebrew word for Hebrew, but Ivrit is its transliteration.)

#### 13.3.1 Conversion of a Full Date

You can convert a full Hebrew date by calling `hebdate` with 3 parameters:

- `hebdate(``day``, mon``, year``)` – In this method of calling `hebdate`, *day* is an INT from 1 to 30 representing the day of the Hebrew month. *mon* is a STRING containing the name of the Hebrew month—either the transliterated version like “Nisan” or the UTF-8-encoded Hebrew version like “ןסינ”. And *year* is an INT representing the *Hebrew* year (so a number greater than or equal to 5750).

Here are some examples:

    SET a hebdate(2, "Shevat", 5786)           Sets a to '2026-01-20'
    SET a hebdate(1, "Tishrey", 5787)          Sets a to '2026-09-12'
    SET a hebdate(30, "Elul", 5790)            Error: Invalid Hebrew date

The final example raises an error because Elul only has 29 days.

#### 13.3.2 Conversion of Partial Dates

Another way to call `hebdate` is as follows:

- `hebdate(``day``, mon [, start``])` – Here, *day* is an INT from 1 to 30 and *mon* is a STRING containing the name of a Hebrew month. *Start* is a DATE (and if *start* is omitted, it defaults to `today()`.)

  When `hebdate` is called this way, it returns (as a DATE) the Gregorian date corresponding to the first Hebrew date on or after *start* that matches *day* and *mon*.

Here are some examples of using `hebdate` to convert partial dates:

    REM [hebdate(1, "Tishrey")] ++7 MSG %"Rosh Hashanah%" is %b.
    REM [hebdate(14, "Adar A")] ++7 MSG %"Purim Katan%" is %b.
    REM [hebdate(25, "Kislev")] ++7 MSG %"Chanukah 1%" is %b.

If, on 2026-01-21, we run the above script through `remind -n`, the output is:

    2026/09/12 Rosh Hashanah is in 234 days' time.
    2027/02/21 Purim Katan is in 396 days' time.
    2026/12/05 Chanukah 1 is in 318 days' time.

Note that Jewish holidays begin at sunset on the day *before* the Gregorian dates returned by `hebdate()`. Thus (for example) Rosh Hashanah in 2026 actually begins at sunset on 2026-09-11.

The `hebdate()` function has other optional parameters that control its behavior in leap years and in years when 30 Heshvan or 30 Kislev do not exist, but a partial date of 30 Heshvan or 30 Kislev was supplied. For details, see the **remind**(1) man page.

## 13.4 A Silly Example

From the point of view of the Gregorian calendar, the date of Chanukah jumps around all over the place, while Christmas is fixed. On the other hand, from the point of view of the Hebrew calendar, Chanukah is fixed while Christmas jumps around. Do the two holidays ever coincide? We can find out with this script:

    REM 25 December SATISFY [hebday($T) == 25 && hebmon($T) == "Kislev"] \
                    MSG Chanukah

Running this in next mode (`remind -n`) in February 2026, yields:

    2027/12/25 Chanukah

Technically, Chanukah begins at sundown on 2027-12-24, but the first day of Chanukah is still considered to be 2027-12-25.

The holidays don’t coincide very often. The next time it happens after 2027 is on 2073-12-25.

If we want to find out when the first day of Passover and Easter Sunday coincide, we can use this script:

    SET $MaxSatIter 100000
    REM SATISFY \
      [$T == easterdate($T) && hebday($T) == 15 && hebmon($T) == "Nisan"] \
      MSG Passover/Easter

Note that because it is *extremely* rare for Easter and Passover to coincide, I had to increase `$MaxSatIter` to 100,000. The next time the holidays coincide is 2123-04-11.
