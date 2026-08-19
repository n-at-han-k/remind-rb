---
title: "Chapter 20: Debugging Remind Scripts"
rules:
  - name: DebugFlagLeftEnabled
    description: >-
      A `DEBUG +flag` with no matching `DEBUG -flag` later in the file. Debug output is
      voluminous and goes to standard error, so a stray `DEBUG +x` turns every later run —
      including the cron one — into a trace log.
  - name: UnknownDebugFlag
    description: >-
      A DEBUG flag letter Remind does not define. An unknown letter is a silently ineffective
      debug session, which is a frustrating way to spend an afternoon.
  - name: DebugCommandsCommitted
    description: >-
      Debugging leftovers in a script that is not being debugged. All of them write to standard
      error on every run. Off by default — while you are debugging they are the point — but
      worth switching on in CI.
---

# Chapter 20: Debugging Remind Scripts

Sometimes, you write a Remind script and it just doesn’t give the results you want or expect. Remind has debugging facilities to help you better understand why a script runs the way it does.

## 20.1 Debug Flags

The `-d` command-line option sets one or more *debug flags*. The syntax of the option is as follows:

`-d``flags`, where *flags* is a sequence of one or more of the following letters:

- `t` – Display all trigger-date computations.
- `x` – Trace all expression evaluation.
- `f` – Trace how Remind opens files (i.e., `INCLUDE` and similar statements).
- `e` – Echo all input lines as they are read.
- `l` – If an error occurs, echo the line that caused it.

There are many more debugging flags (documented in the **remind**(1) man page), but most of them are a bit esoteric or only of interest if you are modifying the source code of Remind itself; the above five flags are the most useful.

All debugging output is sent to standard error.

Debugging output can be *very* voluminous, so Remind has a `DEBUG` command that lets you turn on or of debug flags. For example, if you want to trace trigger computation just for one specific `REM` command, you can put this in your script:

    # Enable the "t" debug flag
    DEBUG +t

    REM tricky-trigger-spec MSG Whatever...

    # Disable the "t" debug flag
    DEBUG -t

Use `DEBUG +``flag...` to enable the corresponding flag or flags and `DEBUG -``flag...` to disable them.

#### 20.1.1 Sample of t Debugging Output

Consider the following script, `tdebug.rem` that contains our old friend, the Friday the 13th reminder:

    REM 13 SATISFY [$Tw == 5] MSG Friday the 13th!

If we run the following command:

    $ remind -dt tdebug.rem 1 December 2025

Then the output is:

    tdebug.rem(1): Trig = Saturday, 13 December, 2025
    tdebug.rem(1): Trig = Tuesday, 13 January, 2026
    tdebug.rem(1): Trig = Friday, 13 February, 2026
    tdebug.rem(1): Trig(satisfied) = Friday, 13 February, 2026

You can see that the first possible trigger date was 2025-12-13. That didn’t satisfy the expression, so Remind kept trying until it found one that satisfied the `SATISFY` expression (as indicated by “Trig(satisfied)”. The final trigger date is 2026-02-13.

#### 20.1.2 Sample of x Debugging Output

Suppose we have a reminder file `xdebug.rem` that contains the following

    FSET sumsq(x, y) x*x + y*y

    SET a max(sumsq(1+2, 2+3), iif(today() > '1990-01-01', 14*2, 97*3))

If we run:

    $ remind -dx xdebug.rem 1 December 2025

Then the result is as follows; I have added the “#” annotation lines.

    # First calculate the arguments to sumsq
    1 + 2 => 3
    2 + 3 => 5

    # Call sumsq
    Entering UserFN sumsq(3, 5)
    x => 3
    x => 3
    3 * 3 => 9
    y => 5
    y => 5
    5 * 5 => 25
    9 + 25 => 34
    Leaving UserFN sumsq(3, 5) => 34

    # Evaluate the first argument of iif
    today() => 2025-12-01
    2025-12-01 > 1990-01-01 => 1

    # First argument of iif is true, so evaluate second argument
    14 * 2 => 28
    iif(1, 28, ?) => 28

    # Finally evaluate the max of the sumsq return value and the iif return value
    max(34, 28) => 34

Note how the `iif` line shows (via a `?`) that the third argument was *not* evaluated. Because the `iif` condition is true, Remind never bothered evaluating the third argument `97*3`.

## 20.2 Other Debugging Commands

Remind has a few other commands useful for debugging your scripts:

    # Dump the OMIT context to standard error
    OMIT DUMP

    # Dump specific variables to standard error
    DUMP a b c xyz $Latitude

    # Dump all normal variables to standard error
    DUMP

    # Dump all system variables to standard error
    DUMP $
