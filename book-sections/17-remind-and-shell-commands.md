---
title: "Chapter 17: Remind and Shell Commands"
rules:
  - name: RunBodyUnquotedSubstitution
    description: >-
      A RUN body that interpolates substitution or pasted-expression output outside shell
      quotes. Remind runs the body through the substitution filter and hands the result to the
      shell. Reminder text is data — a body, a location, a name with an apostrophe — and
      unquoted data in a shell command is a command-injection bug in a calendar.
  - name: RunOnInIncludedFile
    description: >-
      RUN ON in a file that is not the top-level script. It only works at the top level;
      anywhere else it fails, and the script below it runs with RUN still disabled — the failure
      the sandboxing is designed to produce, but silent if you did not mean it.
  - name: ShellUseDefinedWhileRunDisabled
    description: >-
      A function using shell() or RUN defined between RUN OFF and RUN ON. Remind binds the RUN
      permission at definition time, not call time, so the function fails with `RUN disabled`
      even when it is called later with RUN on. The book gives exactly this example.
  - name: WorldWritableScript
    description: >-
      A reminder file that is world-writable, or not owned by the invoking user. Remind flat-out
      refuses a world-writable script and disables RUN for a script it does not own. A linter
      that checks file modes catches this before the cron job does.
  - name: ShellMaxlenArgument
    description: >-
      shell() called with a maxlen that is neither positive nor the negative sentinel.
      `shell(cmd, 0)` returns nothing and looks exactly like a command that produced nothing.
---

# Chapter 17: Remind and Shell Commands

In addition to `MSG`- and `CAL`- type `REM` commands, Remind also supports a `RUN`-type command that looks like this:

    REM trigger RUN body

In this case, rather than printing out the *body* of the reminder, Remind executes it as a shell command, after running it through the substitution filter. For example, if you have a script called `switch-light` that takes an argument of `on` or `off` to turn on or off a smart light, you can have the light come on an hour after sunset and go off 30 minutes before sunrise with this script:

    REM AT [sunrise()-30] RUN switch-light off
    REM AT [sunset()+60]  RUN switch-light on

Note that Remind passes a `RUN`-type reminder’s body through the substitution filter (Section 2.6 on page 15) before executing the result as a shell command.

## 17.1 Daemon Mode

To have the light-switch script work properly, Remind should be started on the computer at boot time and be left running indefinitely. To make this happen, use the `-z` command-line option, which puts Remind in *Daemon Mode*.

In Daemon Mode, Remind does not issue timed reminders when it starts up. Instead, it merely queues them and triggers them at the trigger time. It also periodically checks to see if the script has changed and re-executes itself if so. On Linux, it immediately detects changes to the script using inotify. It also re-executes itself when the date changes. Finally, Remind does not fork and put itself in the background to handle queued reminders if you supply the `-z` flag; instead, it stays in the foreground.

As an example, suppose your user-ID is `user` and you have placed the light-switch script in `/home/user/home-automation.rem`. You could use the following `systemd` unit to start it on boot:

    [Unit]
    Description=Remind script for home automation
    After=network.target

    [Service]
    WorkingDirectory=/home/user
    User=user
    Type=simple
    ExecStart=/usr/local/bin/remind -z /home/user/home-automation.rem
    TimeoutStartSec=0
    Restart=always
    RestartSec=2

    [Install]
    WantedBy=multi-user.target

If your computer does not use `systemd`, then you simply need to come up with a startup script that runs Remind as shown in the `ExecStart` line. You might need to append an `&` to put the script into the background, and potentially redirect standard output and standard error somewhere useful.

## 17.2 The shell function

Remind has a built-in function that executes a shell command and returns whatever was printed to standard output:

- `shell(``cmd [, maxlen``])` – given a STRING *cmd*, run it as a shell command and return the first *maxlen* characters that it emits to standard output. Any whitespace in the output is converted to a space. The trailing newline (if any) is removed.

  If the INT *maxlen* is omitted, it defaults to 511. If it is supplied as a negative number, then it defaults to the system variable `$MaxStringLen`, which is the maximum allowable length of a string (see the **remind**(1) man page.)

Here are examples of ways to use `shell`:

    # hostname is set to the full name of the machine
    SET hostname shell("hostname -f")

    # me is set to the logged-in user-ID
    SET me shell("logname")

## 17.3 Safety

The ability to run shell commands is very powerful, but it also means you need to be wary of running Remind scripts you receive from third parties. Remind has a number of safety features to mitigate the risk:

- The `-r` command-line option unconditionally disables the ability to run shell commands. If you invoke Remind with this option, then `RUN`-type reminders, the `shell()` function, and the `INCLUDECMD` command all fail with the error “RUN disabled.”

- If Remind reads a script that is not owned by the user invoking Remind, then RUN will be disabled during the execution of that script.

- Remind will flat-out refuse to run a script that is world-writable.

- If Remind is run as `root`, which is *emphatically not recommended*, it will not run any scripts that are not owned by `root`.

- You can explicitly disable RUN with the command `RUN OFF` and re-enable it with `RUN ON`. However, `RUN ON` works *only* at the top-level script and not within an included script. So the following could be used to handle a third-party script:

      # This is the top-level file.  We don't quite trust thirdparty.rem
      RUN OFF
      DO thirdparty.rem
      RUN ON

  If `thirdparty.rem` tries to enable RUN with `RUN ON`, it will fail because it is not the top-level script.

- If a function is defined while RUN is disabled, then RUN will also be disabled during the evaluation of the function. For example, the following script will fail with a “RUN disabled” error:

      RUN OFF
      FSET s(x) shell(x)
      RUN ON
      REM MSG [s("echo hello")]

  Even though RUN is enabled when `s()` is evaluated, because it was disabled when `s()` was *defined*, Remind refuses to execute `shell()`.

- If RUN was disabled at the point when a reminder is queued, it will remain disabled when the reminder is issued, even if it is re-enabled before the end of the reminder script.
