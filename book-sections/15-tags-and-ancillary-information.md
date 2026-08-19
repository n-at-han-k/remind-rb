---
title: "Chapter 15: Tags and Ancillary Information"
rules:
  - name: TagSyntax
    description: >-
      A TAG value containing whitespace or a comma. Tags are handed to back-ends as a comma-
      separated list, so a comma inside one splits it into two tags nobody meant.
  - name: DuplicateInfoHeader
    description: >-
      Two INFO clauses on one REM with the same header. The book is explicit that headers cannot
      be duplicated, and equally explicit that they are not case-sensitive, so `Url:` and `URL:`
      on one command are the same collision.
  - name: InfoStringMalformed
    description: >-
      An INFO argument that is not a quoted "Header: value" string. A malformed INFO is dropped
      by the back-end, so the URL or location just never shows up.
  - name: InfoSubstitutionWithoutHeader
    description: >-
      A `%<name>` substitution with no INFO header of that name on the command. It expands to
      the empty string, so the reminder reads `Meeting at ` and looks like a truncation bug.
  - name: InfoHeadersNeedDashPP
    description: >-
      INFO used in a file whose recorded invocation passes plain -p. Plain -p does not carry
      INFO headers to the back-end at all. The reminder is fine, the plumbing is not, and
      nothing reports it.
---

# Chapter 15: Tags and Ancillary Information

Remind has two keywords for associating additional information with a reminder. The `TAG` keyword is used to tag a `REM` statement with a label. This label can be used by back-end programs to identify a specific `REM` command. The TkRemind program, for example, tags all of the reminders it creates with a tag of the form `TKTAG``n`, where *n* is a number. This lets it find the correct command to edit when you click on a reminder to edit it.

The `INFO` keyword, on the other hand, lets you associate arbitrary key/value pairs with a `REM` command. `INFO` is used to associate a URL, a location, a long description, or whatever else you like with a `REM` command.

## 15.1 TAG

To add a tag to a reminder, simply use the `TAG` keyword followed by a tag name. A tag can be any sequence of non-space characters that does not contain a comma. You can use multiple `TAG` keywords in a `REM` command. The syntax is as follows:

    REM trigger TAG tag MSG body

When you run Remind with one of the `-p` options, all of the tags are passed along to the back-end program which can do what it wants with them. Remind itself assigns no special meaning to tags.

## 15.2 INFO

The `INFO` keyword lets you add key/value pairs to a reminder. The syntax looks like this:

    REM trigger INFO "Hdr: value" MSG body

The parameter after the `INFO` keyword is a double-quoted string consisting of a header *Hdr*, a colon, and a value *value*.

The header can be any sequence of non-blank characters (other than a colon) and the value can be anything you like. You can also have as many `INFO` clauses as you want in a `REM` statement, but the headers cannot be duplicated. Header names are not case-sensitive.

**Note:** To pass along `INFO` headers to a back-end, you must use the `-pp` or `-ppp` Remind command-line option. The plain `-p` option won’t work.

Here is an example of how you might use `INFO`:

    REM 12 Feb 2026 AT 15:00 \
       INFO "Url:  https://example.com/videoconference/?id=123954" \
       INFO "Description: Discuss upcoming budget" \
       INFO "Location: Online" MSG Meeting with Dan

The previous example simply puts “Meeting with Dan” in the calendar, but the TkRemind, rem2pdf and rem2html back-ends also turn it into a clickable link. And TkRemind and rem2html will pop up the Description and Location information if you hover over the reminder.

You can use whatever keywords you like for the header, but the back-ends that ship with Remind recognize “Url:”, “Description:” and “Location:” specially.

#### 15.2.1 INFO-related Substitution

In the body of a reminder, the substitution sequence `%<``foo``>` is replaced with the `INFO` string with header *foo:* if it exists, or the empty value if not. Here’s an example:

    REM 12 Mar 2026 AT 9:00 \
        INFO "Location: 235 Main Street" \
        MSG Meeting at %<Location>

On 12 March 2026, the output will be:

    Meeting at 235 Main Street

#### 15.2.2 URLs in the Terminal

If a reminder has a “Url:” `INFO` header, then in Agenda Mode or in Calendar Mode in the terminal, Remind will use the OSC-8 specification to turn the body of the reminder into a hyperlink. Not all terminals support this; a partial list of terminals that do support it is at https://github.com/Alhadis/OSC8- Adoption/?tab=readme-ov-file.

If the display of reminders with “Url:” headers is messed up in your terminal, you can disable the OSC-8 escape sequences by setting this system variable in your reminder script:

    SET $TerminalHyperlinks 0

By default, \$TerminalHyperlinks is set to 1, which enables the terminal-mode hyperlinking.
