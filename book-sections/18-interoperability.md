---
title: "Chapter 18: Interoperability"
rules:
  - name: SecretCalendarUrl
    description: >-
      A private calendar URL or credential committed in a reminder script. The book's warning,
      made mechanical: anyone with the secret link can read the calendar. Reminder files get
      committed to dotfile repos more casually than almost anything else on a machine.
  - name: ConvertedFileHandEdited
    description: >-
      Hand edits in a file that ics2rem or radicale-remind regenerates. The next sync overwrites
      them. With radicale-remind the Remind script *is* the source of truth in the other
      direction, so knowing which files are which side of the sync matters.
  - name: RecurrenceNotExportable
    description: >-
      A reminder whose recurrence rem2ics can only export as a date list. Those events export as
      a finite RDATE list, so they stop existing on the phone once the exported window runs out.
      Useful to know at authoring time for a file destined for export; noise everywhere else.
---

# Chapter 18: Interoperability

While Remind is a great calendar for a Linux or UNIX desktop, most people have mobile devices with their own calendar software. Synchronizing calendar data between Remind and mobile devices is therefore quite desirable.

## 18.1 iCalendar and CalDAV

Most calendar tools exchange calendar data in a format called *iCalendar*, specified in RFC 5545 available at https://www.rfc-editor.org/rfc/rfc5545. The iCalendar format is a pretty flexible format for specifying events and tasks, and can handle many types of recurrences. iCalendar data is often stored in files whose names end with `.ics`. The term “iCalendar” is often shortened to “iCal” even though the official name of the specification is “iCalendar”.

*CalDAV* is a standard for exchanging iCalendar data over HTTP or HTTPS. It is used both to download events into a client that then displays the events on a calendar, and to upload events to synchronize any modifications made on the client with the data stored on the calendar server.

Remind itself does not include tools to synchronize calendar data, but there are several third-party tools to make this happen. They rely on converting Remind events to iCalendar data or vice-versa.

A good set of tools for converting from iCalendar to Remind and vice-versa is the Python `remind` library at https://pypi.org/project/remind/ maintained by Jochen Sprickerhof. This includes Python libraries for doing the conversion as well as `rem2ics` and `ics2rem` command-line tools. In the following section, I will describe how to use the Python tools. On my Debian 13 machine, I installed them as root with the following command:

    # pip3 install --break-system-packages remind

Despite the ominous `--break-system-packages`, no system packages were harmed.

## 18.2 Importing Calendars into Remind

To import a Google or Apple calendar into Remind, you first have to export it as an iCalendar file. You can get a link to your calendar by going to “Settings” for the specific calendar and copying the “Secret address in iCal format” link, which will look something like this:

    https://calendar.google.com/calendar/ical/myaddr%40gmail.com/private-

    9039db38b8983b891b8923b89821b092/basic.ics

This will give you a URL that you can fetch automatically with `wget` or `curl`. Be sure not to give out the secret link; anyone who has it can see your calendar!

If you use other calendar systems, such as Apple’s calendar, you need to research to figure out how to get the calendar in iCalendar format; there should be a way.

Once you have the iCalendar file, convert it it Remind by running:

    $ ics2rem icalfile.ics import.rem

The file *import.rem* will contain your calendar in Remind format. You can automate this by creating a script to do the conversion and running it periodically from `cron`.

You can get help about additional options for `ics2rem` by running:

    $ ics2rem --help

## 18.3 Exporting Calendars From Remind

To export your Remind calendar to iCalendar format, use the `rem2ics` command:

    $ rem2ics file.rem file.ics

Again, you can get help by running:

    $ rem2ics --help

Because the types of recurrences that Remind can support are far richer than those that can be expressed by the iCalendar format, `rem2ics` directly converts only reminders with simple recurrences, such as weekly recurrences, to an `RRULE` property. For other reminders, it essentially runs `remind -ppp` and specifies a list of dates with an `RDATE` property attached to the event.

Once you have your Remind events in iCalendar format, you should be able to import them to your Google or Apple calendar. I recommend keeping a separate calendar dedicated to imported Remind events.

Jochen Sprickerhof also maintains a remind-caldav tool at https://github.com/jspricke/remind-caldav that lets you synchronize Remind calendars to and from CalDAV servers. This lets you automatically synchronize your Google and Remind calendars. I don’t recommend two-way synchronization. Instead, keep a separate reminder file for downloading your main Google calendar, and a separate Google calendar for uploading whatever reminder files you want to synchronize to Google.

## 18.4 Running Radicale

Rather than using a cloud provider such as Google, Apple or Microsoft to store your calendar, you can run your own CalDAV server. A good choice is Radicale, found at https://radicale.org/.

Radicale is an easy-to-configure CalDAV server written in Python. It stores calendar data in individual iCalendar files under a specific directory, and serves them to clients using the CalDAV protocol. You can also update the files using CalDAV if you have sufficient permission.

`remind-caldav` works with any CalDAV server. On my Web site, I describe how I set up my own Radicale server and use it to synchronize my mobile devices with each other and with my Remind installation on my workstation. The article is at https://dianne.skoll.ca/writings/de-googling-my-life/.

## 18.5 Radicale Remind Storage

Jochen Sprickerhof has a project called Radicale Remind Storage at https://github.com/jspricke/radicale- remind that offers an alternate way to keep your Remind calendars synchronized with mobile devices.

`radicale-remind` is a plugin for the Radicale CalDAV server. Rather than storing events as individual iCalendar files, `radicale-remind` offers a storage back-end that stores events as Remind scripts. That is, if you create an event using CalDAV, it ends up creating a `REM` command in a Remind script.

The Remind scripts created by `radicale-remind` may be used directly by Remind, and serve as the single “source of truth” for your calendar events. Modifying the Remind scripts automatically modifies the events served by Radicale using CalDAV, and modifying a calendar entry via CalDAV automatically updates the Remind script.
