---
title: "The Book of Remind — Front Matter"
rules: []
---

# The Book of Remind

by Dianne Skoll

Copyright 2026 Dianne Skoll

Version 1.3 - 2026-05-05

## Dedication

For Wayne and Rebecca

## Copyright

This book is Copyright 2026 by Dianne Skoll. Except as noted in the license below, all rights are reserved.

## License

If you are a Human Being, you may:

1.  Read this book and make verbatim copies for your personal use.
2.  Distribute verbatim copies of this book *at no charge* to other Human Beings (who then become subject to this License), with the following restriction: You may *not* place a copy of this book on a publicly-accessible Web server or FTP server or similar unless you take effective measures to ensure that it is only downloaded by humans and is not accessible to AI scrapers. Password- protecting access to the book would be considered an effective measure providing the password does not appear in plain-text on the server.

**No part of this book may be used or reproduced in any manner for the purpose of training artificial intelligence technologies or systems.**

**Dianne Skoll expressly reserves this work from the text and data mining exception in the European Copyright Directive.**

## Acknowledgments

Although I wrote this book and Remind mostly by myself, the book and Remind have been immeasurably improved by the community of Remind users, especially those on the Remind-Fans mailing list.

I’d like to thank Tim Chase for reviewing an early draft of this book and for providing valuable feedback. He’s written an extensive blog post about Remind at https://blog.thechases.com/posts/remind/, and has suggested many useful features that have made it into the software.

Thanks to Jochen Sprickerhof for reviewing this book, maintaining the Debian package of Remind and for writing the tools mentioned in Chapter 18 that allow synchronization of Remind calendars with calendars on other devices. He’s also contributed many small fixes to Remind and the Remind man pages.

Thanks to Neil Hanlon for maintaining the EPEL Remind package.

Thanks to Ian! D. Allen for suggesting many improvements to Remind and to its documentation, and for contributing to the project financially.

The following people have also made contributions to Remind, submitted bug reports, donated to my Liberapay account, or have written software that works with Remind:

Ron Aaron, Valerio Aimale, Davide Alberani, Justin Alcorn, Mark Atwood, Greg Badros, Robert Black, Jim Budler, Jin Chen, Rafa Couto, Liviu Daia, Ian Darwin, Björn Davíðsson, Michael DeBusk, Larry De Coste, Laurent Duperval, Paul M. Foster, Daniel Graham, Gail Gurman, Darrel Hankerson, Russ Herman, Tina Hoeltig, Patric Hof, Robert Joop, Jonathan Kamens, Willem Kasdorp, Richard Kelly, Joop Kiefte, Mathieu Laparie, Nimrod Levy, Tom Limoncelli, Mogens Lynnerup, Christopher J. Madsen, Shelagh Manton, Marek Marczykowski, John McGowan, Judah Milgram, Michael Neuhauser, Ed Oskiewicz, Marco Paganini, Paul Pelzl, Francois Pinard, Trygve Randen, Dave Rickel, Michael Salmon, David W. Sanderson, Randal L. Schwartz, Amos Shapir, Mikko Silvonen, Georg Simon, George M. Sipe, Jerzy Sobczyk, Detlef Steuer, David W. Tamkin, Wolfgang Thronicke, Frank Vance, Erik-Jan Vens, Norman Walsh, Tug Williams, Dave Wolfe, Hong Wu, Arthur G. Yaffe, and Frank Yellin,

I may well have missed some names; if so, please accept my apologies and also let me know so I can add your name to this list.

## Donations

This book, like Remind, is free. However, should you wish to contribute financially to the Remind project, donations are gratefully accepted at Liberapay. The donation link is https://dianne.skoll.ca/donate.php?rbook

# Contents

- **1 Introduction 1**
  - 1.1 What is Remind? — 1
  - 1.2 A Brief History of Remind — 2
  - 1.3 A Quick Example — 3
  - 1.4 The Organization of This Book — 4
- **2 File Structure and Basic Reminders 7**
  - 2.1 The Structure of a Remind Script — 7
    - 2.1.1 Commands — 7
    - 2.1.2 Comments — 8
    - 2.1.3 Blank Lines — 8
    - 2.1.4 Continued Lines — 8
    - 2.1.5 Character Set and Encoding — 9
    - 2.1.6 Case Sensitivity — 9
  - 2.2 Running Remind — 9
    - 2.2.1 Some Remind Command-Line Options — 10
  - 2.3 The REM Command: An Introduction — 11
  - 2.4 The Remind Trigger-Calculation Algorithm — 14
  - 2.5 Advance Warning — 14
  - 2.6 The Substitution Filter — 15
    - 2.6.1 Some Substitution Sequences — 16
    - 2.6.2 Limiting the Text in Calendar Mode — 16
  - 2.7 The Banner — 16
  - 2.8 Counting Backwards — 17
  - 2.9 Some Syntactic Sugar — 18
    - iii
  - 2.10 Checking What Will Happen on a Specific Date — 19
  - 2.11 The “Current” Date and Time — 19
  - 2.12 Running Remind Multiple Times in a Row — 20
- **3 Holidays and Other Exceptions 21**
  - 3.1 Local OMITs — 23
  - 3.2 Saving and Restoring the Omit Context — 24
  - 3.3 Dumping the OMIT Context — 24
  - 3.4 Alternate Forms of Back and Delta — 24
- **4 More Advanced Reminders 27**
  - 4.1 Arbitrary Recurrences — 27
  - 4.2 Specific Expiry Dates — 28
  - 4.3 Specific Starting Dates — 28
  - 4.4 Movable Holidays — 28
    - 4.4.1 Safe Movable Holidays — 30
- **5 Timed Reminders 33**
  - 5.1 The `AT` Clause — 33
    - 5.1.1 Queuing Reminders — 34
    - 5.1.2 Fine Control over Queuing — 34
  - 5.2 Some Time-Related Substitution Sequences — 34
  - 5.3 Advance Warning — 35
  - 5.4 Specifying Durations — 35
  - 5.5 Syntactic Sugar for a Specific Date and Time — 36
  - 5.6 Priority — 36
  - 5.7 Sorted Output in Agenda Mode — 36
- **6 Expressions 39**
  - 6.1 Variables — 39
  - 6.2 System Variables — 39
  - 6.3 Data Types — 40
  - 6.4 Constants — 41
  - 6.5 True and False Values — 42
  - 6.6 Operators — 43 6.7 Order of Evaluation — 44
  - 6.8 Description of Operators — 44
    - 6.8.1 Unary Negation Operators — 44
    - 6.8.2 Multiplication, Division and Modulus — 45
    - 6.8.3 Addition — 45
    - 6.8.4 Subtraction — 46
    - 6.8.5 Comparison — 47
    - 6.8.6 Equality and Inequality Operators — 47
    - 6.8.7 Logical AND — 47
    - 6.8.8 Logical OR — 48
  - 6.9 Built-In Functions — 48
    - 6.9.1 Some Built-In Functions — 49
  - 6.10 User-Defined Functions — 52
    - 6.10.1 Redefining a Function — 53
  - 6.11 Recursive Functions — 53
  - 6.12 Commands for Manipulating Variables and Functions — 54
    - 6.12.1 Unsetting a Variable — 54
    - 6.12.2 Saving and Restoring Variables — 54
    - 6.12.3 Unsetting a Function — 54
    - 6.12.4 Saving and Restoring Functions — 54
  - 6.13 Expressions and Reminders — 55
- **7 The SATISFY Keyword 57**
  - 7.1 The Operation of SATISFY — 58
  - 7.2 SATISFY Iteration Limit — 59
  - 7.3 Useful Functions and System Variables — 60
  - 7.4 A SATISFYing Gallery — 61
    - 7.4.1 The Fifth Weekday of a Month — 61
    - 7.4.2 Observed vs. Actual Holidays — 61
    - 7.4.3 US Presidential Election Day — 62
    - 7.4.4 Credit Card Due Date — 62
    - 7.4.5 Recycling Date — 63
    - 7.4.6 End-of-Quarter — 64
- **8 Some Callback Functions 65**
  - 8.1 OMITFUNC — 65
  - 8.2 The WARN Keyword — 66
  - 8.3 The SCHED Keyword — 67
  - 8.4 Prefix and Suffix Callback Functions — 67
  - 8.5 Sortbanner — 68
- **9 File Inclusion and Flow Control 71**
  - 9.1 File Inclusion — 71
    - 9.1.1 INCLUDE — 71
    - 9.1.2 DO — 71
    - 9.1.3 SYSINCLUDE — 72
  - 9.2 Conditional Execution — 72
    - 9.2.1 The `IF` Command — 73
    - 9.2.2 The `IFTRIG` Command — 74
  - 9.3 Reading Scripts from Directories — 74
  - 9.4 Command Inclusion — 75
- **10 TODOs 77**
  - 10.1 The TODO Keyword — 77
  - 10.2 TODOs and Calendar Mode — 78
- **11 Astronomical Events 79**
  - 11.1 Location — 79
  - 11.2 Sunrise and Sunset — 80
  - 11.3 Moon-Related Functions — 81
    - 11.3.1 Moon Phases — 81
    - 11.3.2 Moonrise and Moonset — 82
    - 11.3.3 Blue Moons — 83
  - 11.4 Solstices and Equinoxes — 83
  - 11.5 Easter — 83
- **12 Producing Calendars 85**
  - 12.1 Calendars in the Terminal — 85
    - 12.1.1 If Your Terminal Calendar Displays are Messed Up — 86
  - 12.2 Additional Calendar-Related Command-Line Options — 86
    - 12.2.1 First Day of the Week — 86
    - 12.2.2 Size of the Calendar — 86
    - 12.2.3 Time Format — 87
  - 12.3 Machine-Readable Calendar Output — 87
  - 12.4 PDF Calendars — 88
    - 12.4.1 Generating PostScript and SVG Instead of PDF — 89
  - 12.5 HTML Calendars — 89
  - 12.6 Restricting Reminders to Calendar Mode or Agenda Mode — 90
  - 12.7 Special Data for Calendars — 90
    - 12.7.1 SHADE — 91
    - 12.7.2 MOON — 92
    - 12.7.3 WEEK — 93
    - 12.7.4 COLOR — 93
    - 12.7.5 Coloring Reminders by Default — 98
  - 12.8 Back-End-Specific SPECIALs — 99
    - 12.8.1 Rem2PDF SPECIAL: PANGO — 99
    - 12.8.2 Rem2HTML SPECIALs — 100
- **13 The Hebrew Calendar 101**
  - 13.1 A Description of the Hebrew Calendar — 101
  - 13.2 Gregorian-to-Hebrew Conversion — 102
  - 13.3 Hebrew-to-Gregorian Conversion — 103
    - 13.3.1 Conversion of a Full Date — 104
    - 13.3.2 Conversion of Partial Dates — 104
  - 13.4 A Silly Example — 105
- **14 The TkRemind Graphical Front-End 107**
  - 14.1 Main Window — 109
    - 14.1.1 Keyboard Shortcuts — 109
  - 14.2 Queued Reminders — 110
  - 14.3 Printing The Calendar — 110
  - 14.4 Options — 111
    - 14.4.1 Basic Options — 112 14.4.2 Running a Command When Popping Up a Queued Reminder — 113
    - 14.4.3 Miscellaneous Options — 113
    - 14.4.4 Appearance — 114
  - 14.5 Adding Reminders — 115
    - 14.5.1 Basic Recurrences — 116
    - 14.5.2 Options — 116
    - 14.5.3 The Reminder Body — 117
  - 14.6 Editing Reminders — 117
  - 14.7 URLs, Location and Description — 118
  - 14.8 The Queue — 118
  - 14.9 Errors — 118
  - 14.10Automatically Adjusting to Changes — 118
  - 14.11Variables Set by TkRemind — 118
  - 14.12Getting Help — 119
- **15 Tags and Ancillary Information 121**
  - 15.1 TAG — 121
  - 15.2 INFO — 121
    - 15.2.1 INFO-related Substitution — 122
    - 15.2.2 URLs in the Terminal — 122
- **16 Time Zones 125**
  - 16.1 Reminders in a Specific Time Zone — 125
    - 16.1.1 How `TZ` works — 126
  - 16.2 Time Zone Conversion Functions — 127
  - 16.3 Validating Time Zone Names — 128
- **17 Remind and Shell Commands 129**
  - 17.1 Daemon Mode — 129
  - 17.2 The shell function — 130
  - 17.3 Safety — 131
- **18 Interoperability 133**
  - 18.1 iCalendar and CalDAV — 133
  - 18.2 Importing Calendars into Remind — 134 18.3 Exporting Calendars From Remind — 134
  - 18.4 Running Radicale — 135
  - 18.5 Radicale Remind Storage — 135
- **19 Localization 137**
  - 19.1 The `TRANSLATE` Command — 137
  - 19.2 Functions and Filter Sequences — 138
  - 19.3 Localizing the Substitution Filter — 139
    - 19.3.1 Simplified Callbacks for Today/Tomorrow/Something Else — 140
    - 19.3.2 Custom Substitution Callbacks — 140
  - 19.4 Overriding `ord()` — 141
  - 19.5 How To Localize Remind — 141
    - 19.5.1 LANGID — 141
    - 19.5.2 The Banner — 142
    - 19.5.3 System Variables — 142
    - 19.5.4 Messages — 142
  - 19.6 More on `TRANSLATE` — 142
  - 19.7 Back-Ends — 143
- **20 Debugging Remind Scripts 145**
  - 20.1 Debug Flags — 145
    - 20.1.1 Sample of `t` Debugging Output — 146
    - 20.1.2 Sample of `x` Debugging Output — 146
  - 20.2 Other Debugging Commands — 148
- **21 Going Further 149**
  - 21.1 Example Project — 149
  - 21.2 Wrapping Up — 150
- **A Getting and Installing Remind 151**
  - A.1 Prerequisites — 151
  - A.2 Obtaining Remind — 151
    - A.2.1 Downloading the Source Code — 151
    - A.2.2 Prerequisites for Building Remind — 151
  - A.3 Building Remind — 153 A.4 Installing Remind — 153
  - A.5 Uninstalling Remind — 153
- **B Calendar Systems 155**
  - B.1 Reconciling Days, Months and Years — 155
  - B.2 Year Numbering — 157
  - B.3 Calendar Systems supported by Remind — 157
- **C Bibliography 159**
