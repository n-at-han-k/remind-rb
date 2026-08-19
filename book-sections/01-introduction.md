---
title: "Chapter 1: Introduction"
rules:
  - name: ScriptFileExtension
    description: >-
      A linted file whose name is neither *.rem nor .reminders. A reminder file that Remind
      never loads looks like a Remind bug rather than a naming mistake.
---

# Chapter 1: Introduction

Welcome! If you are reading this book, then you are probably interested in learning how to use the Remind calendar program.

<sup>1</sup> Remind does ship with fairly extensive documentation, but it’s in the form of a UNIX man page that expands to about 80 printed pages. While man pages make great reference material (and indeed, I encourage you to read the Remind man page from beginning to end) they are not particularly good as tutorials. This book aims to supplement the man page by teaching you how to use Remind step-by-step.

<sup>2</sup> By the way: In several places in this book, I will write: “... see the **remind**(1) man page.” What this means is that you should open a terminal on your computer and type: `man remind`. Then read the resulting text.

## 1.1 What is Remind?

Remind is a sophisticated calendar and alarm program designed to run on Linux and other UNIX-like systems. Remind is primarily a *command-line* program. Although Remind does ship with a graphical front end (described in Chapter 14), you need to be comfortable with editing script files and using the UNIX command line in a terminal to get the most out of Remind.

<sup>3</sup> To use Remind, you use your favorite text editor to create a plain-text file called a *Remind script*. Be sure to create a *plain-text* file using a text editor for writing scripts or programs; using a word-processor will not produce a plain text file suitable for consumption by Remind.

A Remind script contains a sequence of commands that Remind reads and interprets. The output from interpreting the commands depends on how Remind is invoked; it could be a set of reminders for today, it could be a calendar drawn in your terminal, or it could be a machine-readable calendar suitable for

> <sup>1</sup> UNIX manual pages are called “man pages” because the command to read them is `man`. <sup>2</sup> Referring to man pages as “**remind**(1)” is a UNIX tradition. It means that the man page is in Section 1 of the manual, which is devoted to user commands. You don’t actually type the `(1)` part when you want to read the man page. <sup>3</sup> Your favorite text editor is Emacs, right?

post-processing by another program.

In this book, I will distinguish between UNIX commands that you enter at the shell prompt, and Remind commands that you put in a Remind script, as follows: UNIX commands will be written in lower-case, like this: `remind` or `rem2ps`, while Remind commands will be written in upper-case, like this: `REM` or `OMIT`.

Remind’s scripting language is an example of a *domain-specific language* or DSL. It’s designed to let you express very concisely all kinds of complicated date specifications. As you’ll see later on, not only can Remind do simple things like remind you of weekly appointments or of people’s birthdays, but it can also do more complex things like reminding you of the second full moon in a calendar month, or telling you when sunrise and sunset are.

Remind never really started out with any roadmap or design goals, as will be evident in the next section. However, gradually a primary design goal became clear, and it is this:

Remind must be able to represent events with arbitrarily-complicated recurrence rules, so you only need to write the script *once* and Remind will *always* get the date of the events correct.

<sup>4</sup> As an example, my garbage-collection day is every second Wednesday, but it is deferred by one day if the previous Monday or Tuesday or the Wednesday itself is a holiday. My city sends out calendars to show when collection day is. It also has a web site where you can look it up. And there’s even a mobile device app for this, because heaven knows the world has a severe lack of mobile device apps.

“This is nonsense!” I thought. I want a way to tell my computer when garbage-collection day is and then have it get it right *every single time*.

And the goal was achieved.

## 1.2 A Brief History of Remind

Back in my student days, in the Mesozoic era of computing, I had an MS-DOS PC and that sufficed for my computing needs. But in 1989, I had my first exposure to this strange new operating system called UNIX. I quickly grew to appreciate the power of UNIX: If the UNIX command line were the equivalent of a suave and articulate scholar, the MS-DOS command line would be like a grunting stone-age hominid flailing about trying to create this thing called “language”.

So I liked UNIX. And UNIX came with a command called `calendar`. This command would read a little text file and print a list of upcoming reminders. It was extremely simplistic, but I liked it. When my UNIX job ended, I was back in MS-DOS purgatory and I really missed `calendar`. So I decided to write a replacement, and in late 1989, Remind was born.

> <sup>4</sup> What Canadians call “garbage-collection” might be called “trash-collection” if you’re American or “rubbish-collection” if you’re British.

At the time, I was a novice C programmer and had very little clue what I was doing. I also had no experience with calendars or date calculations. The iCalendar standard was almost a decade in the future, so I just hacked away at Remind until it did what I wanted.

In 1990, I changed cities and took a job that once again gave me access to UNIX. At the time, there was a thing called Usenet which was effectively a giant distributed bulletin board system, where anyone could post and read whatever they wanted. To bring some semblance of order to this chaos, Usenet was divided into topics called *newsgroups* and one newsgroup was called `comp.sources.misc`. People would post the source code of interesting programs they’d written, and anyone could compile and use the programs. So I put the source to Remind up on `comp.sources.misc` and a few people started using it.

Remind development really picked up in 1992. I had started working on my Master’s Thesis, so of course I procrastinated by doing what I really liked... hacking on Remind. Apart from a break from 2005-2007, I’ve been working on Remind in my spare time ever since. And it has developed into a pretty... *full- featured*... program.

I hope you persist and don’t fear the command-line. Wrangling Remind into doing a complicated date calculation is one of the most satisfying things you can do on a computer; I hope you agree with me and enjoy the little dopamine hit. I’ve enjoyed many dopamine hits from writing Remind.

## 1.3 A Quick Example

“OK!” I hear you say, “but show us an example of Remind working!”

If you haven’t already installed Remind on your system, see Appendix A on page 151 for instructions on how to do so. Go ahead... I’ll wait while you do that.

OK, now that Remind is installed, let’s create a little text file called `reminders.txt`. It should have the following content:

    REM 1 January MSG New Year's Day
    REM Wednesday MSG Piano lesson
    REM 4 January MSG Bill's Birthday

Now, let’s run Remind on that file. In this example, I am running Remind on Tuesday, 19th August 2025. The first line below is the shell prompt followed by what I typed in, and the rest is the output from Remind.

    $ remind reminders.txt
    No reminders.

Isn’t that exciting?? But suppose instead I had run Remind on Wednesday, 1st January 2025. What do we get then?

    $ remind reminders.txt
    Reminders for Wednesday, 1st January, 2025 (today):

    New Year's Day

    Piano lesson

That’s a bit more like it! (Though in reality, my piano teacher wouldn’t have been teaching on New Year’s Day. We’ll see later on how to tell Remind about this fact.)

In this book, I will often write “run the following script...” or words to that effect. What I really mean is:

1.  Create a text file containing the commands in the example.
2.  Run `remind filename` from the shell prompt, possibly with some extra `remind` command-line arguments or options.

Conventionally, Remind scripts are either called `.reminders` or file names that end in `.rem`, but Remind doesn’t care what you name your script files.

By the way... in the examples above, I showed a little dollar sign, `$`, on the command-line. Don’t actually type that in. It just signifies that you need to type the bold part in as a shell command and then press Enter. In the few cases where you need to run a command as *root*, I will indicate that with a `#` shell prompt instead of the usual `$`

## 1.4 The Organization of This Book

This book has a *lot* of chapters. Chapters 2 through 7 are required reading. You should also read chapters 9, 12, and 14. The other chapters can be deferred until you need to use a feature they describe.

- Chapter 2 introduces you to the basics of writing a Remind script. It describes the overall syntax of a script and introduces you to basic types of reminders, such as one-off reminders and reminders with very simple recurrences.
- Chapter 3 explains how Remind handles holidays and exceptions that modify otherwise-regular recurrences.
- Chapter 4 talks about more advanced recurrences as well as how Remind can handle movable holidays (for example, holidays that are specified as something like “The first Monday in September”).
- Chapter 5 talks about reminders that also have a time-of-day associated with them (such as an appointment or a meeting) and how Remind can queue them and issue them at the right time.
- Chapter 6 talks about variables and expressions, important parts of Remind that are used to create very sophisticated recurring reminders.
- Chapter 7 talks about the `SATISFY` keyword which works together with expressions to express very complicated kinds of reminders. For example, suppose your credit card bill is due 21 days after the 15th of each month, unless that falls on a holiday or weekend, in which case the due date is delayed until after the holiday or weekend. You can express such a reminder with `SATISFY`.
- Chapter 8 describes a few more features that you can use for complex recurrences or scheduling, as well as so-called *callback functions* for modifying the appearance of a reminder.
- Chapter 9 describes how Remind scripts can be split up across several files that are included by a main file. It also describes the `IF` command that allows conditional flow control through a Remind script.
- Chapter 10 describes Remind’s facilities for TODO-style reminders. These are different from normal reminders because Remind keeps reminding you about them until you explicitly mark them as complete.
- Chapter 11 describes Remind’s features for handling astronomical events such as moon phases, sunrise and sunset, solstices and equinoxes. It also describes Remind’s built-in support for calculating the date of Easter (both Western and Orthodox).
- Chapter 12 describes how to use Remind (and in some cases, some helper programs) to produce calendars in the terminal, as PDF output and as HTML output.
- Chapter 13 describes Remind’s support for the Hebrew calendar.
- Chapter 14 describes TkRemind, a graphical front-end for Remind. This lets you make use of Remind without needing to learn the Remind scripting language (although I still recommend that you learn it).
- Chapter 15 describes facilities for adding ancillary information to a reminder, such as a location, a URL, or a long description.
- Chapter 16 describes Remind’s facilities for expressing reminders in a specific time zone that might not be the same as your computer’s default time zone.
- Chapter 17 describes Remind’s facilities for running commands at specified dates and times.
- Chapter 18 describes tools to synchronize Remind calendars with other calendar services, such as those used on mobile devices.
- Chapter 19 describes how you can localize Remind (that is, translate it into a non-English language).
- Chapter 20 describes some features Remind has that let you debug problems with your Remind scripts.
