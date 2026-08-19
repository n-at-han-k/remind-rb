---
title: "Appendix A: Getting and Installing Remind"
rules:
  - name: FeatureNewerThanTargetVersion
    description: >-
      A keyword, function or system variable newer than the Remind version the project targets.
      Distributions ship old Remind. A script written against 06.02 that has to run on the
      Remind in Debian stable fails at parse time on the target machine and nowhere else, which
      is the worst place to find out.
  - name: SyntaxRuleNeedsRemind
    description: >-
      The Syntax rule is enabled but `remind` is not on PATH. Otherwise every file reports the
      same spawn failure as if it were a defect in the file.
---

# Appendix A: Getting and Installing Remind

## A.1 Prerequisites

To run Remind, you need a UNIX-like operating system. Remind runs on Linux, FreeBSD, OpenBSD, NetBSD, Solaris, Mac OS X, and pretty much any reasonable UNIX-like system. It does not run on Windows, though you can run it in a Linux virtual machine under Windows.

## A.2 Obtaining Remind

Many Linux distributions pre-package Remind. Therefore, you can install it with your normal package manager commands (for example, `apt` on Debian-derived systems; `dnf` on RedHat-derived systems, and so on.) However, the version packaged with your operating system may be out of date, so I encourage you to install Remind from source. Not only is this good practice for installing from source in general, but it also ensures you have the most up-to-date version of Remind.

#### A.2.1 Downloading the Source Code

Remind’s home page is dianne.skoll.ca/projects/remind/ and that page has links to download the source code. The source code filename will be something like `remind-``xx``.``yy``.``zz``.tar.gz` where *xx*, *yy* and *zz* are two-digit numbers specifying the primary, secondary, and minor release numbers.

#### A.2.2 Prerequisites for Building Remind

Remind itself has very few prerequisites—all it needs as a working C build environment. The specifics for obtaining this vary across UNIX systems; consult your system’s documentation. Here’s what you need for a couple of popular Linux distributions:

- For Debian and Debian-derived systems:

      # apt install build-essential

- For recent Red Hat-like systems:

      # dnf install @c-development @development-tools

If you want readline support so that `remind -` supports interactive command editing, you will need the following:

- For Debian and Debian-derived systems:

      # apt install libreadline-dev

- For recent Red Hat-like systems:

      # dnf install readline-devel readline

If you want to build `rem2pdf`, the tool that produces PDF calendars, you additionally need a Perl environment and the Perl modules `Cairo`, `Encode`, `ExtUtils::MakeMaker`, `Getopt::Long`, `JSON::MaybeXS` and `Pango`. These prerequisites also suffice for installing `rem2html`, a program that produces HTML calendars.

Consult your system’s documentation to figure out how to install the prerequisites. Again, for a couple of popular Linux distributions:

- For Debian and Debian-derived systems:

      # apt install libcairo-perl libjson-maybexs-perl libpango-perl perl

- For recent Red Hat-like systems:

      # dnf install perl-Cairo perl-JSON-MaybeXS perl-Pango \
      perl-base perl-lib perl-libs

If you want to install `tkremind`, the graphical front-end for Remind, you need Tcl/Tk, the Noto fonts, and the tcllib library.

- For Debian and Debian-derived systems:

      # apt install fonts-noto-core fonts-noto-color-emoji \
      fonts-noto-extra fonts-noto-ui-core fonts-noto-ui-extra tk tcllib

- For recent Red Hat-like systems:

      # dnf install google-noto-sans-fonts google-noto-serif-fonts \
      google-noto-emoji-fonts tk tcllib

## A.3 Building Remind

The following steps will build Remind. You should *not* run any of the steps below as *root*; instead, run them as an ordinary user.

- Unpack the downloaded tar file:

      $ tar xvf remind-xx.yy.zz.tar.gz

- Change into the unpacked directory:

      $ cd remind-xx.yy.zz

- Configure Remind:

      $ ./configure

  By default, Remind will be installed under `/usr/local`. If you prefer it to be installed under `/usr`, run the following configuration command instead:

      $ ./configure --prefix=/usr

- Build Remind:

      $ make

- (Optional) Run the test suite:

      $ make test

## A.4 Installing Remind

Installing Remind requires you to run the following command as *root* from within the directory where you just built Remind:

    # make install

## A.5 Uninstalling Remind

If you think you will ever want to uninstall Remind, then immediately after installing it, you can type:

    $ make uninstall-script > ../uninstall-remind.sh

(You can and should run the above command as an ordinary user rather than as *root*.)

This creates a shell script called `../uninstall-remind.sh` that will, if run as root, uninstall the version of Remind that was just installed.
