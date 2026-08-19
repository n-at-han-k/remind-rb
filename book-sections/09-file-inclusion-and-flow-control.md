---
title: "Chapter 9: File Inclusion and Flow Control"
rules:
  - name: IncludeRelativePath
    description: >-
      INCLUDE with a relative pathname, where DO is meant. INCLUDE resolves a relative path
      against the current working directory, not the including file's directory — the book calls
      this arguably a mistake kept for compatibility. The script then works from one directory
      and fails from another. DO resolves relative to the file.
  - name: IncludeTargetMissing
    description: >-
      A DO, INCLUDE or SYSINCLUDE naming a file that is not there. A typo'd include is a whole
      file of reminders that silently never fire.
  - name: SysIncludeAbsolutePath
    description: >-
      SYSINCLUDE with an absolute pathname. For absolute paths SYSINCLUDE is just INCLUDE, so
      the keyword is misleading: it reads as if it pointed into the system include directory
      when it does not.
  - name: IncludeCmdUnquotedPaste
    description: >-
      An INCLUDECMD whose shell text interpolates `[expr]` outside quotes. Everything after
      INCLUDECMD is shell, not Remind. An unquoted paste splits on whitespace at best and
      executes at worst — the book's own example is careful to write `L="[lessons]"`.
  - name: IfNestingTooDeep
    description: >-
      IF blocks nested past Remind's limit of 64. 65 levels is an error. (The book's footnote
      suggests that at that depth the script has larger problems.)
  - name: IftrigWithSatisfy
    description: >-
      An IFTRIG whose trigger-spec contains a SATISFY clause. IFTRIG accepts any trigger a REM
      would, *except* SATISFY. The exclusion is easy to miss when copying a REM into an IFTRIG.
---

# Chapter 9: File Inclusion and Flow Control

Remind lets you organize your reminders into different files using the `INCLUDE` family of commands. It also has facilities for conditionally executing portions of a script.

## 9.1 File Inclusion

We saw earlier that Remind is invoked with the name of a file containing the reminder script. It’s often convenient to organize your reminders into several files. For example, you might want one file holding public holidays, another holding birthdays, a third holding work events, and so on.

The `INCLUDE` family of commands lets you do this.

#### 9.1.1 INCLUDE

The `INCLUDE` command’s syntax is as follows:

    INCLUDE pathname
    INCLUDE "pathname"

The first variant may be used if the pathname does not contain any spaces. If the pathname does contain spaces, then use the second double-quote-enclosed form.

#### 9.1.2 DO

If you supply a relative pathname to the `INCLUDE` command, then the file is taken from the current working directory, *not* the directory containing the file with the `INCLUDE` command. This is arguably a mistake, but can’t be changed for historical reasons. To fix this, we have the `DO` command:

    DO pathname
    DO "pathname"

For absolute pathnames, `DO` is equivalent to `INCLUDE`. For relative pathnames, `DO` reads the file relative to the directory containing the file with the `DO` command, rather than relative to the current working directory.

`DO` is the most convenient command for organizing your files. For example, you might have a `main.rem` file that includes all of your other files:

    DO holidays.rem
    DO birthdays.rem
    DO work.rem
    DO personal.rem

#### 9.1.3 SYSINCLUDE

The final command for file inclusion is `SYSINCLUDE`. It looks like this:

    SYSINCLUDE pathname
    SYSINCLUDE "pathname"

For absolute pathnames, `SYSINCLUDE` is equivalent to `INCLUDE`. Relative pathnames, however, are treated relative to an installation-defined *system include directory*. Remind ships with many useful reminder files containing holidays for various countries, Chinese New Year dates, and so on, and they all live in the system include directory. For example, to get a reminder of Chinese New Year, you can use:

    SYSINCLUDE holidays/chinese-new-year.rem

The system include directory’s location is stored in a system variable called `$SysInclude`. You can find out where the directory is by running this Remind script:

    REM MSG System Include Directory is: [$SysInclude]

It’s likely to be something like `/usr/share/remind` or `/usr/local/share/remind`. I encourage you to rummage around in this directory and look at some of the reminder files included with Remind.

## 9.2 Conditional Execution

Remind has a couple of commands that let you conditionally execute certain parts of a script.

#### 9.2.1 The IF Command

The general format of the `IF` command is as follows:

`IF expression # True-block of commands.. ELSE # False-block of commands.. ENDIF` The `ELSE` part can be omitted, so you can also have just this:

    IF expression
        # True-block of commands..
    ENDIF

`IF` works as follows:

1.  The *expression* is evaluated.
2.  If the result is a true value (Section 6.5 on page 42), then all of the commands in the *True-block of commands* are executed.
3.  Otherwise, if there is an `ELSE` clause, then all of the commands in the *False-block of commands* are executed.
4.  `ENDIF` is mandatory.

The indentation shown in the examples is just for clarity; it is not required although I recommend you use <sup>1</sup> it. Also, `IF` commands may be nested up to a limit of 64 levels.

For an example of how you might use `IF`, suppose you’ve organized your reminders into separate files as show in Section 9.1.2 on page 71. And suppose you want an option *not* to include work reminders in some cases. You could write the main file like this:

    DO holidays.rem
    DO birthdays.rem
    IF ! catch(exclude_work, 0)
        DO work.rem
    ENDIF
    DO personal.rem

Now, you can invoke Remind in the following ways:

> <sup>1</sup> If you actually write a Remind script with 64 nested levels of `IF`, it’s time to re-evaluate your approach to life.

    $ remind main.rem
    $ remind -iexclude_work=1 main.rem

The first command includes all of your reminders. The second one uses a command-line option `-i` to define a variable on the command-line. The `IF` expression evaluates false if `exclude_work` is true, so the `DO work.rem` command is skipped.

#### 9.2.2 The IFTRIG Command

The `IFTRIG` command lets you conditionally execute parts of a script based on whether or not a trigger specification would trigger. The general format is as follows:

    IFTRIG trigger_spec
        # True-block of commands..
    ELSE
        # False-block of commands..
    ENDIF

The *trigger_spec* is any trigger specification that would be accepted by a `REM` command, *not including* a `SATISFY` clause. If the *trigger_spec* would trigger today, then the *True-block of commands* is executed. If not, then the *False-block of commands* is executed. As with `IF`, the `ELSE` part is optional.

Here is an example:

    IFTRIG Mon 1 SEP SCANFROM -7 ++8
        # Executed on the first Monday in September
        # and the preceding 8 days
    ELSE
        # Executed on all other days
    ENDIF

While `IFTRIG` looks like a powerful and useful command, I find it is almost never needed. It’s almost always better to have each `REM` command compute its own trigger date from scratch.

## 9.3 Reading Scripts from Directories

If the pathname you supply to Remind either on the command-line or in a `DO` or `INCLUDE` command is a *directory* rather than a plain file, then Remind looks inside the directory for files that match the shell pattern `*.rem` and reads them in sorted order (the same sorted order that `echo *.rem` would produce.)

Conventionally, the default name for a Remind script is `.reminders` in your home directory. I made a *directory* called `.reminders` that holds all my `*.rem` files. This makes it very easy to organize reminders; I can simply drop in or delete a `*.rem` file where that makes sense.

You might want to name your files starting with two or three decimal digits to ensure a consistent sort order. For example, here are some of the files that live in my `.reminders` directory:

    000-preamble.rem
    010-sun.rem
    030-chinese-new-year.rem
    062-holidays.rem
    064-library-books.rem
    080-misc.rem
    082-domain-expiries.rem
    100-tkremind.rem
    101-birthdays.rem

## 9.4 Command Inclusion

The `INCLUDE` family of commands has one more member you haven’t seen yet: `INCLUDECMD`. Rather than opening a file, `INCLUDECMD` executes a shell command, whose output is expected to be a Remind script.

This can let you do powerful things. For example, you could write a script that looks up events in a database and emits `REM` commands to create reminders for them. Or you could write a script that pulls down an online iCal calendar and converts it to a Remind script.

Here is an example of how you can (ab)use `INCLUDECMD`. Suppose you have four driving lessons scheduled in July, 2026. One is on the 6th at 10:00; another is on the 9th at 14:00; the third is on the 16th at 17:00 and the last one is on the 20th at 12:00. There’s no obvious pattern to these reminders, so you’d normally write them as separate reminders. However, you could also write a script like this:

    SET lessons "2026-07-06@10:00 2026-07-09@14:00 " + \
                "2026-07-16@17:00 2026-07-20@12:00"

    INCLUDECMD L="[lessons]" ; total=`echo $L | wc -w`; n=0; for i in $L ; \
               do n=`expr $n + 1`; \
               echo "REM $i MSG Driving Lesson ($n of $total)"; done

Note that all of the text after `INCLUDECMD` is a *shell script* and is *not* written in Remind’s scripting language. The only exception is the expression-pasting of `[lessons]` used to initialize the shell variable `L`.

If we run the above script with the `-n` option, we get:

    2026/07/06 10:00am Driving Lesson (1 of 4)
    2026/07/09 2:00pm Driving Lesson (2 of 4)
    2026/07/16 5:00pm Driving Lesson (3 of 4)
    2026/07/20 12:00pm Driving Lesson (4 of 4)

If your driving lesson schedule changes, you merely need to edit the `SET lessons` line and everything else will adjust. Whether you consider this trick a thing of beauty or a horror show is up to you.
