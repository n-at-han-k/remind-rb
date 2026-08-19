---
title: "Chapter 19: Localization"
rules:
  - name: SubstitutionCallbackSignature
    description: >-
      A subst_* or ordx callback defined with the wrong arity. Remind calls these by name. A
      three-argument contract met with two means the callback is never used and the substitution
      silently falls back to English.
  - name: SubstitutionCallbackUnknownSequence
    description: >-
      A subst_ callback for a sequence Remind does not have, or a %{name} with no callback. Both
      fail quietly — a callback that is never called, or a sequence that expands to nothing. The
      `x` variants only apply to the today/tomorrow family (%a %b %c %e %f %g %h %i %j %k %l %u
      %v), which is a checkable list.
  - name: TranslationFormatSpecifiers
    description: >-
      A TRANSLATE whose translated string does not carry the same %-escapes, in the same order,
      as the English. Remind rejects the translation outright and warns, so the message silently
      stays English. The same-order requirement is a real constraint on translators and exactly
      the kind of thing a linter should carry for them.
  - name: LangidNotTranslated
    description: >-
      A localization file that never translates LANGID. LANGID reverts to "en" when
      untranslated, so scripts that branch on `_("LANGID")` take the English path in a fully
      translated pack.
  - name: TranslateCommandForm
    description: >-
      A TRANSLATE that is none of the five valid forms. Anything else is a parse error, and the
      bare-word forms are easy to mistype into a translation of the literal string "CLEAR".
  - name: SystemVariableVersusTranslate
    description: >-
      Day and month names localized through $-variables in a file that also uses TRANSLATE. They
      are exactly equivalent — setting one updates the other — so mixing both styles in one pack
      is a consistency question, not a correctness one. Off by default; the shipped language
      packs use the system-variable form deliberately.
---

# Chapter 19: Localization

Not everybody speaks English or wants calendars with English month and day names. Remind has a localization mechanism called the *translation table* that lets you translate the normal English words and phrases that it outputs into another language.

Note that localization is applied only to *output*. If you localize your version of Remind for the Dutch language, for example, it will happily output “maandag” instead of “Monday”, but in your reminder scripts, you still have to specify day names and month names with their English names; Remind will *not* recognize “maandag” in *input*.

## 19.1 The TRANSLATE Command

To add a string to the translation table, use the `TRANSLATE` command. The syntax is:

    TRANSLATE "English-phrase" "Translated-phrase"

For example, if you want to translate all of the day names from English to Dutch, you could use:

    TRANSLATE "Sunday" "zondag"
    TRANSLATE "Monday" "maandag"
    TRANSLATE "Tuesday" "dinsdag"
    TRANSLATE "Wednesday" "woensdag"
    TRANSLATE "Thursday" "donderdag"
    TRANSLATE "Friday" "vrijdag"
    TRANSLATE "Saturday" "zaterdag"

If we execute the above commands in a script followed by:

    REM MSG Vandaag is %w.

and we run the script on Monday, 2026-02-02, we get:

    Vandaag is maandag.

## 19.2 Functions and Filter Sequences

Remind has a single built-in function for doing a translation lookup as well as a special substitution sequence that also does translation lookups. The function is `_`, a single underscore that takes one STRING argument, and the substitution sequence is `%(``string``)`.

Examples are probably the best way to illustrate how they work:

    TRANSLATE "Sunset" "Zonsondergang"
    TRANSLATE "Monday" "maandag"

    REM MSG [_("Monday")]         Outputs "maandag"
    REM MSG %(Monday)             Outputs "maandag"

    SET a _("Tuesday")            Sets a to "Tuesday"
    REM MSG %(Monday) %(Tue)      Outputs "maandag Tue"

    SET a _("Sunset")             Sets a to "Zonsondergang"
    SET a _("sunset")             Sets a to "zonsondergang"

Note a few things:

- If a string is not in the translation table, then both the function `_("``string``")` and the substitution sequence `%(``string``)` simply return *string* unmodified.
- If a lower-case string such as `sunset` does not exist in the translation table, then Remind tries the mixed-case version `Sunset`. If that exists, then the result is converted to lower case and returned, as in the last example above. Note, however, that this *only* works if the first letter is ASCII.
- If a lower-case string such as `sunset` exists in the translation table and you ask for a translation of `Sunset`, then Remind tries the lower-case version `sunset`. If that exists, then the result is converted to mixed case and returned. Again, this *only* works if the first letter isASCII. If you need translations for case variants of non-ASCII words, you should explicitly add `TRANSLATE` commands for each variant.

## 19.3 Localizing the Substitution Filter

The simple `TRANSLATE` mechanism is not good enough to localize substitution sequences such as `%b`. Recall that `%b` is replaced by “today”, “tomorrow”, or “in *n* days’ time” depending on the relationship between today and the trigger date.

To handle substition filter localization, Remind lets you define *callback functions* that override the normal operation of the filter sequence. These are simply user-defined functions named `subst_``x`, where *x* is the substitution sequence you wish to override.

For example, let’s say we want to localize `%b` to Dutch. Consider this example:

    FSET subst_b(alt, date, time) \
       iif(date == $U, "vandaag", \
           date == $U+1, "morgen", \
           "over " + (date-$U) + " dagen")

    REM 26 Feb 2026 +10 MSG Tandarts afspraak %b

The results of running the above file are:

    # On 2026-02-23
    Tandarts afspraak over 3 dagen

    # On 2026-02-24
    Tandarts afspraak over 2 dagen

    # On 2026-02-25
    Tandarts afspraak morgen

    # On 2026-02-26
    Tandarts afspraak vandaag

The substitution callback `subst_``n` is passed three arguments in the following order:

- `alt` is an INT which is 0 if the substitution sequence was `%``n` or 1 if it was `%*``n`. The alternate forms of substitution slightly change the output; see the **remind**(1) man page for details.
- `date` is a DATE which is the reminder’s trigger date.
- `time` is a TIME. If the reminder has an `AT` clause, then `time` is the trigger time. Otherwise, it is set to `now()`.

The return value of the substitution function replaces the original substitution sequence.

#### 19.3.1 Simplified Callbacks for Today/Tomorrow/Something Else

Many callbacks such as `%b` return “today”, “tomorrow”, or something else, depending on if the trigger date is today, tomorrow, or further in the future. You can simplify your localization as follows:

    TRANSLATE "today" "vandaag"
    TRANSLATE "tomorrow" "morgen"

    FSET subst_bx(alt, date, time) "over " + (date-$U) + " dagen"

    REM 26 Feb 2026 +10 MSG Tandarts afspraak %b

This produces exactly the same output as the previous version. But note that the `subst_bx` function is much simpler than the earlier `subst_b` function. That is because it is called *only* for cases that don’t match “today” or “tomorrow”.

The substitution sequences that output “today”, “tomorrow” or something else and that meaningfully support the `subst_``n``x` variants are: `%a`, `%b`, `%c`, `%e`, `%f`, `%g`, `%h`, `%i`, `%j`, `%k`, `%l`, `%u`, and `%v`. See the **remind**(1) man page for details about those substitution sequences.

The substitution sequences `%:`, `%!`, `%?`, `%@`, and `%#` contain characters that are illegal in a function name. They may be overridden with functions names `subst_colon`, `subst_bang`, `subst_question`, `subst_at`, and `subst_hash`, respectively, and also support variants with the letter `x` appended.

#### 19.3.2 Custom Substitution Callbacks

In addition to overriding built-in substitution sequences, you can create new ones of your own. Suppose you have a reminder every Wednesday, but if the Wednesday happens to fall on the 18th of a month, you want to suffix it with “ - WOOT!”. Here’s how you could do it. Suppose we create a file called `wedwoot.rem` with the following contents:

    FSET subst_wedwoot(alt, date, time) iif(day(date)==18, " - WOOT!", "")
    REM Wednesday MSG Meeting%{wedwoot}

Then running the command:

    $ remind -s wedwoot.rem 2026-02-01

gives us:

    2026/02/04 *   * Meeting
    2026/02/11 *   * Meeting
    2026/02/18 *   * Meeting - WOOT!
    2026/02/25 *   * Meeting

The substitution sequence `%{``anything``}` will attempt to call a function `subst_``anything` with the usual `alt`, `date` and `time` arguments, and its return value will replace the entire sequence.

## 19.4 Overriding ord()

As we saw in Section 6.9.1 on page 49, the `ord(``n``)` function returns a string that is the ordinal number *n* (for example, `"1st"`, `"13th"`, `"423rd"`, etc. For non-English languages, you can override the behavior of `ord` by defining your own `ordx` function. If this function is defined, then calling `ord` ends up calling `ordx` instead.

Some languages have quite complicated rules for generating ordinal numbers; here is an excerpt from the Finnish localization script that ships with Remind:

    FSET ord_helper(d) iif(d==1, ":senä", d==2, ":sena", \
                          (d%10)==2||(d%10)==3||(d%10)==6||(d%10)==8, ":ntena", \
                           ":ntenä")
    FSET ordx(d) d + ord_helper(d)

## 19.5 How To Localize Remind

Remind ships with a number of localization packages; they are installed in the directory `$SysInclude/lang` and are named something like `lc``.rem`, where *lc* is the lower-case two-letter ISO 639-1 language code. You can examine those files to get a feel for how to localize Remind.

To generate a template for making your own localization file, simply run this shell command:

    $ echo 'TRANSLATE GENERATE' | remind -h - > template.rem

(The `-h` command-line option suppresses the `No reminders.` message that Remind normally prints if there are no reminders.)

The generated template has several parts for you to adjust:

#### 19.5.1 LANGID

The special string `LANGID` should always be translated to the ISO 639-1 language code of your translation file. For example, if you are creating a translation file for Swedish, then you should put this at the top of the file:

    TRANSLATE "LANGID" "se"

`LANGID` is extra-special in that if you don’t translate it, or you clear out its translation, it reverts to `"en"`. A Remind script can query the language by calling `_("LANGID")`.

#### 19.5.2 The Banner

Next, comes a translation for the banner. Replace the default:

    BANNER Reminders for %w, %d%s %m, %y%o:

with a localized version for your language.

#### 19.5.3 System Variables

Next come a whole lot of system variables holding translations of day names, month names, and various other phrases. These are leftovers from when the only way to localize Remind was to set various system variables rather than using the `TRANSLATE` command. The template uses system variables for consistency with existing language packs. However, the following pairs of commands are *completely equivalent*:

    SET $Monday "lundi"
    TRANSLATE "Monday" "lundi"

    SET $June "Junio"
    TRANSLATE "June" "Junio"

Setting the system variable will also create a `TRANSLATE` entry, and translating the English default value of the system variable will also update the system variable.

#### 19.5.4 Messages

Finally, there is a large section for translating error messages and other messages issued by Remind. Update the translations by editing the second quoted string in each `TRANSLATE` command.

If the English version of a string has `printf-`style escape sequences (`%``x`), then the localized version must have the *same* escape sequences in the *same* order as the English version, or the translated version will not be used and Remind will issue a warning. I realize that requiring the same order can be a bit constraining, but that’s something translators have to live with.

In addition to the foregoing, a proper localization script will also localize the substitution filter. Check the language files in `$SysInclude/lang/` for examples.

## 19.6 More on TRANSLATE

In addition to the syntax shown in Section 19.1 on page 137, there are other ways to use `TRANSLATE`, as shown below:

    # Translate "string" to "tekenreeks"
    TRANSLATE "string" "tekenreeks"

    # Remove the translation entry for "string"
    TRANSLATE "string"

    # Remove all translation table entries
    TRANSLATE CLEAR

    # Emit TRANSLATE commands to standard output
    # that reflect the current translation table
    TRANSLATE DUMP

    # Generate a translation table template on standard output
    TRANSLATE GENERATE

## 19.7 Back-Ends

If you run Remind with the `-p`, `-pp` or `-ppp` option, it transmits the entire translation table to the back-end in JSON format. Back-ends are expected to respect the translations (and all of the back-ends that ship with Remind do so.) Thus, if you localize Remind, you also localize TkRemind, Rem2PDF, and Rem2HTML “for free”.
