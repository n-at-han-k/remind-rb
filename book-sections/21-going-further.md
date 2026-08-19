---
title: "Chapter 21: Going Further"
rules: []
---

# Chapter 21: Going Further

You now have a thorough understanding of Remind. But this book still hasn’t covered all of the features of Remind such as purge mode, daemon mode, server mode, and a whole lot of other system variables and built-in functions. As always, I refer you to the **remind**(1) man page.

Remind is an open-source program released under the terms of the GNU General Public License, Version 2. As such, I encourage you to read its source code, found under the `src/` directory in the source package. Some of the code is old and convoluted, such as the trigger calculation algorithms in `trigger.c` and `dorem.c`, and I’m not too proud of it.

But some of the code is newer and better, such as the expression-evaluation engine in `expr.c` and I’m very proud of that.

If you like Remind, I encourage you to use it. And if you really like it, why not write programs that interoperate with it, such as `rem2pdf`, `tkremind` or the ICS-to-Remind and Remind-to-ICS tools? Perhaps Remind will spark your imagination and get you started on your own programming projects.

## 21.1 Example Project

Here’s an example of a project I made recently that uses Remind. I wanted a digital clock in my bedroom, but I wanted one that automatically adjusted for Daylight Saving Time, and I also wanted one that would synchronize to NTP servers on the Internet so it always displayed an accurate time.

As it happens, I had a spare Raspberry Pi Zero W lying around. I bought a 32x8 LED matrix display and wrote a program to display the time on the LED matrix. Once a minute, this program gets Remind to run a tiny Remind script to determine if the Sun is above or below the horizon. If it’s after sunset, but before sunrise, the clock program dims the LED display. Otherwise, it brightens it.

Now, while I could have used a light sensor to adjust the display brightness according to the ambient light, I didn’t have a light sensor handy, but I did have Remind handy.

## 21.2 Wrapping Up

This book, like Remind, is free. However, should you wish to contribute financially to the Remind project, donations are gratefully accepted at Liberapay. The donation link is https://dianne.skoll.ca/donate.php?rbook
