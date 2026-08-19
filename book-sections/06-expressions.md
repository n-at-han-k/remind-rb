---
title: "Chapter 6: Expressions"
rules:
  - name: UndefinedVariable
    description: >-
      A variable read in an expression that the file never SETs. Remind stops with `Undefined
      variable: `name'`. Where the value legitimately comes from outside — `remind -ivar=1` —
      the fix is `catch(var, default)`, which the message can suggest.
  - name: FunctionRedefinition
    description: >-
      A second FSET of a name already defined in the file, without the `-` form. Remind warns on
      redefinition. `FSET - name(...)` is the way to say the redefinition is deliberate, and the
      linter can point at it.
  - name: OperandTypeMismatch
    description: >-
      An operator applied to literal operands of a type it does not accept. The type rules in
      6.8 are exact, so a literal-only expression can be checked without running anything. `9 /
      14:33` is an error today and a mystery next month.
  - name: CrossTypeEqualityAlwaysFalse
    description: >-
      `==` or `!=` between literals of different types. Operands of different types are never
      equal — `"foo" == 14:33` is a constant 0. Whatever the author meant, it was not that.
  - name: IntConstantOutOfRange
    description: >-
      An INT constant outside the C int range. Remind's INT is the platform's C int; a bigger
      literal wraps or errors depending on where it lands.
  - name: InvalidStringEscape
    description: >-
      A backslash escape Remind does not define, or `\x00`. The escape set is closed and `\x00`
      is prohibited outright — a NUL cannot appear inside a Remind string.
  - name: DateConstantBeforeEpoch
    description: >-
      A DATE or DATETIME constant before 1990-01-01, or malformed. 1990-01-01 is Remind's
      beginning of time. Dates below it cannot be represented at all.
  - name: PushVarsMissingName
    description: >-
      A variable SET between PUSH-VARS and POP-VARS that the PUSH-VARS never named. PUSH-VARS
      only saves what you list, so an unlisted assignment leaks past the POP — which is the one
      thing the block was there to stop.
  - name: RecursionDepthExceeded
    description: >-
      A recursive FSET called with a literal argument that exceeds Remind's 1000-call limit.
      `sum_to(3000)` is not slow, it is an error — `Too many recursive function calls` — and the
      limit is hard.
---

# Chapter 6: Expressions

So far, you’ve seen that Remind has some pretty powerful ways to specify events. I’m going to switch gears in this chapter and talk about *expressions*, a part of Remind that at first blush seems to have absolutely nothing to do with specifying events. But don’t worry; we’ll tie it all together before the end of this chapter.

## 6.1 Variables

A variable in Remind (as with many other programming languages) is simply a named slot that can hold a *value*. In Remind, variables are *global* and can have names consisting of letters, numbers and underscores, though the first character must be a letter or an underscore.

You set the value of a variable using the `SET` command. Here are some examples:

    SET adv_warning 7
    SET message "I'm sorry Dave, I'm afraid I can't do that"

The first `SET` command sets the variable `adv_warning` to the integer value `7`. The second `SET` command sets the variable `message` to the string value `"I'm sorry Dave, I'm afraid I can't do that"`.

## 6.2 System Variables

Remind has another type of variable called a *system variable*. These variables’names always begin with `$`. Unlike normal variables that can be brought into existence simply with a `SET` command, system variables always exist and only a specific list of system variables exists; you can’t create new ones.

System variables have a multitude of uses, but generally they are used to query something about the internals of Remind, or to alter the behavior of Remind.

For example, the system variable `$DontQueue` returns 1 if Remind was invoked with the `-q` command- line option, or 0 if not. It is read-only: You can use it in an expression, but you cannot `SET` it.

An example of a writable system variable is `$AddBlankLines`. Normally, Remind adds a blank line between reminders in Agenda Mode, but if you `SET $AddBlankLines` to `0`, then these blank lines are not added.

Writable system variables have restrictions on what values they can be `SET` to. Remind will issue an error if you try to set a system variable to a value that it does not support.

This book will document some system variables; for an exhaustive list, see the **remind**(1) man page.

## 6.3 Data Types

A variable has no intrinsic data type; it simply takes on the type of whatever value it was last set to. Remind itself has five data types:

1.  `INT` - an integer. Remind’s INT type uses the underlying C *int* type. If your machine uses 32-bit twos-complement arithmetic for the C *int* type (which most modern UNIX systems do), then the Remind INT type can range from -2 147 483 648 to 2 147 483 647.

2.  `STRING` - a string of bytes or characters. By default, strings can be a maximum of 65535 bytes long, though this limit can be changed at run-time by setting the system variable `$MaxStringLen`. In Remind, a STRING can be viewed in two ways:

    \(a\) As a sequence of *bytes*. From this viewpoint, a string is just a sequence of 8-bit numbers from `1` to `255`, terminated by a byte of `0`.

    \(b\) As a sequence of *characters*. From this viewpoint, a string is a sequence of UNICODE characters where some characters might require multiple 8-bit bytes (so-called *multibyte strings*.) Even from this viewpoint, a string is still terminated by a byte of `0`, which cannot appear in the middle of a string.

    Remind has functions for processing strings from both points of view. If you are using a UTF-8 locale (which you really, really should be doing) then the character interpretation of strings assumes they are validly UTF-8-encoded.

    If you know for sure that all of your strings are ASCII, then the byte-oriented functions can be used safely and are faster than the character-oriented functions. If you are using non-ASCII characters, then it’s better to use the character-oriented functions.

3.  `DATE` - a date (with granularity one day) on or after 1990-01-01. Internally, Remind stores DATE types as the number of days since 1990-01-01.

4.  `TIME` - a time of day (with granularity one minute). A TIME can range from 00:00 (midnight) to 23:59. Internally, Remind stores TIME types as the number of minutes since midnight. Any

    arithmetic on a TIME type is done modulo the number of minutes in a day (which happens to be 1440.)

5.  `DATETIME` - a date and time with granularity one minute. Internally, Remind stores DATETIME types as the number of minutes since 1990-01-01@00:00.

## 6.4 Constants

A constant is a value that is fixed—for example, the number 7 or the date 2026-09-04. Each of the five Remind data types has rules for how you write a constant of that type:

1.  An INT constant is written as a sequence of decimal digits, optionally preceded by a minus sign. You can also write an INT constant in hexadecimal by preceding it with `0x`. Here are some examples of INT constants:

        7
        2029
        -45
        0xFE01

2.  A STRING constant is written as a sequence of zero or more characters enclosed in double-quotes. Here are some examples of STRING constants:

        ""
        "Hello, world!"
        "This here: \" is a quote"
        "Here is a newline.\n"

    The first example is the *empty string* consisting of no characters. The last two examples show some *backslash escapes*. Remind supports the following backslash escapes:

    - `\a` - the bell character (ASCII character 7.)
    - `\b` - the backspace character (ASCII character 8.)
    - `\f` - the form-feed character (ASCII character 12.)
    - `\n` - the newline character (ASCII character 10.)
    - `\r` - the carriage-return character (ASCII character 13.)
    - `\t` - the horizontal tab character (ASCII character 9.)
    - `\v` - the vertical tab character (ASCII character 11.)
    - `\\` - a literal backslash.
    - `\"` - a double-quote character.
    - `\x``ab` - here, *a* and *b* are hexadecimal digits and the corresponding byte is inserted into the string. The sequence `\x00` is not permitted.

3.  A DATE constant is written in the form YYYY-MM-DD or YYYY/MM/DD, *enclosed in single- quotes*. Here are some date constants:

        '2025-02-28'
        '1999/01/01'
        '2040-12-31'

4.  A TIME constant is written in the form HH:MM or HH.MM. Normally, HH ranges from 00 to 23 (meaning times are written in 24-hour format). However, you can append “am” or “pm” to write times in 12-hour format. Here are some time constants:

    `14:45 9.13 2:45pm` (which is equivalent to `14:45`)

5.  A DATETIME constant is written as a date followed by either @ or T followed by a time, all enclosed in single quotes. Here are some DATETIME constants:

        '2025-12-31@14:45'
        '1990/01/01T00.00'
        '2055-02-22@09:30'

## 6.5 True and False Values

Every data type has a *zero value* which is treated as **false** in contexts where a logical true/false value is expected. Every value *other than* the zero values is treated as **true**. The zero values for the various types are:

- `INT 0`
- `STRING ""` (the empty string)
- `DATE '1990-01-01'`
- `TIME 00:00`
- `DATETIME '1990-01-01@00:00'`

## 6.6 Operators

An *operator* performs a calculation on one or more values, resulting in a new value. For example, consider the following two SET commands:

    SET a 5 * 6
    SET b a + 2

In the first SET command, the operator `*` is a multiplication operator; it operates on its *operands*, namely `5` and `6` to yield the product, `30`. So after this SET command is executed, the variable `a` is set to the value `30`.

In the second SET, command, the operator `+` is an addition operator. It adds its two operands, namely `a` (which has just been assigned the value 30) and `2` to yield `32`, and that is the value assigned to `b`.

This second example shows how to write an expression containing a variable; wherever a value is expected, you simply write the variable’s name. If you use a variable that has not yet been assigned a value, an error results. For example, this script:

    SET a 45 * nonexistent_variable

yields the following error:

    Undefined variable: `nonexistent_variable'

Here are all of the operators Remind supports, listed in order of highest to lowest precedence. The first two (`!` and `-`) are *unary operators* that appear just before their only operand. The remaining operators are *binary operators* that appear between their two operands.

<sup>•</sup> `!` and `-` (logical negation and arithmetic negation) <sup>•</sup> `*`, `/` and `%` (multiplication, division and modulus) <sup>•</sup> `+` and `-` (addition and subtraction) <sup>•</sup> `<`, `<=`, `>` and `>=` (comparisons) <sup>•</sup> `==` and `!=` (equality and inequality tests) <sup>•</sup> `&&` (logical AND) <sup>•</sup> `||` (logical OR)

## 6.7 Order of Evaluation

Remind uses the following rules when evaluating an expression:

1.  Operators with higher precedence are evaluated before operators with lower precedence.

2.  Operators with the same precedence are *always* evaluated from left to right.

3.  Parentheses may be used to change the order of evaluation.

        SET a 4 + 5 * 6
        SET b (4 + 5) * 6
        SET c 4 + 5 + "Hello"

In the first example, `5 * 6` is evaluated first, yielding `30`, and then `4 + 30` is evaluated, yielding a final value of `34` which is stored in `a`.

In the second example, parenthesis change the order of evaluation. `4 + 5` is evaluated first, yielding `9`. Then `9 * 6` is evaluated yielding a final value of `54` for `b`.

In the third example, `4 + 5` is evaluated first, yielding `9`. Then `9 + "Hello"` is evaluated. In this context, the `+` operator acts as a concatenation operator, so the final result stored in `c` is the STRING `"9Hello"`. The third example shows that the `+` operator is not necessarily associative, so the left-to-right evaluation rule becomes important.

## 6.8 Description of Operators

#### 6.8.1 Unary Negation Operators

The logical operator `!` precedes its operand. The operand can be any type. If the operand is one of the zero values (Section 6.5 on page 42) then `!` evaluates to the INT `1`. Otherwise, it evaluates to the INT `0`. Here are some examples:

    SET a !3                           (a is set to 0)
    SET b ! ""                         (b is set to 1)

The arithmetic operator `-` precedes its operand, which must be of type INT. It returns the negative of its operand. Here are examples:

    SET a - 44                         (a is set to -44)
    SET b -a                           (b is set to 44)

#### 6.8.2 Multiplication, Division and Modulus

The `*` operator takes two operands. If both operands are of type INT, then it returns the product of its operands. If one operand *n* is of type INT (and is non-negative) and the other operand *s* is of type STRING, then it returns a STRING consisting of *n* copies of *s*, Here are some examples:

    SET a 9 * -3                       (a is set to -27)
    SET b 3 * "bar"                    (b is set to "barbarbar")
    SET c b * 2                        (c is set to "barbarbarbarbarbar")

The `/` operator takes two operands, both of which must be of type INT. It returns the integer part of the quotient of the first operand divided by the second. Some examples:

    SET a 9/2                          (a is set to 4)
    SET b (-8)/2                       (b is set to -4)

The `%` operator takes two operands, both of which must be of type INT. It returns the remainder of the first operand divided by the second. Some examples:

    SET a 9%2                          (a is set to 1)
    SET b (-8)%2                       (b is set to 0)

#### 6.8.3 Addition

The `+` operator takes two operands of various types. Here are all the combinations that are supported:

- If both operands are of type INT, the result is also of type INT and is the sum of the operands.
- If one operand *d* is of type DATE and the other operand *n* is of type INT, the result is of type DATE and is the date found by adding *n* days to *d*.
- If one operand *t* is of type TIME and the other operand *n* is of type INT, the result is of type TIME and is the time found by adding *n* minutes to *t*, modulo 24 hours. That is, the result will *always* range from `00:00` through `23:59`.
- If one operand *dt* is of type DATETIME and the other operand *n* is of type INT, the result is of type DATETIME and is the time found by adding *n* minutes to *dt*.
- If at least one operand is of type STRING, then both operands are converted to type STRING. The result is a string that is the concatenation of the two strings.

Here are some examples:

    SET a 9 + 21                       (a is set to 30)
    SET a '2024-02-01' + 365           (a is set to '2025-01-31')
    SET a 14:33 + 900                  (a is set to 05:33)
    SET a '2026-07-03@05:45' + 199     (a is set to '2026-07-03@09:04')
    SET a "Hello, " + "world."         (a is set to "Hello, world.")

#### 6.8.4 Subtraction

The `-` operator takes two operands of various types. Here are all the combinations that are supported:

- If both operands are of type INT, the result is also of type INT and is the result of subtracting the second operand from the first.
- If both operands are of type DATE, the result is of type INT and is the number of days from the first operand to the second. The result is negative if the first operand is later than the second.
- If both operands are of type TIME, the result is of type INT and is the number of minutes from the first operand to the second. The result is negative if the first operand is later than the second.
- If both operands are of type DATETIME, the result is of type INT and is the number of minutes from the first operand to the second. The result is negative if the first operand is later than the second.
- If the first operand *d* is of type DATE and the second *n* is of type INT, the result is a DATE found by subtracting *n* days from *d*.
- If the first operand *t* is of type TIME and the second *n* is of type INT, the result is a TIME found by subtracting *n* minutes from *t*, modulo the number of minutes in a day.
- If the first operand *dt* is of type DATETIME and the second *n* is of type INT, the result is a DATETIME found by subtracting *n* minutes from *dt*.

Here are some examples:

    SET a 9 - 7                        (a is set to 2)
    SET a '2025-01-01' - '2024-01-01'  (a is set to 366)
    SET a 04:33 - 02:33                (a is set to 120)
    SET a '2025-01-31@00:00' - \
          '2025-01-01@00:00'           (a is set to 43200)
    SET a '2025-01-01' - 33            (a is set to '2024-11-29')
    SET a 03:45 - 600                  (a is set to 17:45)
    set a '2026-01-31@12:00' - 6000    (a is set to '2026-01-27@08:00')

#### 6.8.5 Comparison

The operators `<`, `<=`, `>` and `>=` take two operands. The operands may be of any type, but must both be of the same type.

The operators `<`, `<=`, `>` and `>=` return `1` if and only if the first operand is strictly less than the second, less than or equal to the second, strictly greater than the second, or greater than or equal to the second, respectively. Otherwise, they return `0`.

String comparisons are done byte-by-byte. All other comparisons are done numerically, with later DATEs, TIMEs and DATETIMEs being considered greater than earlier ones.

Here are some examples:

    SET a 9 < 7                        (a is set to 0)
    SET a 14:33 <= 14:33               (a is set to 1)
    SET a '2025-01-01' > '2024-12-31'  (a is set to 1)
    SET a "fox" >= "dog"               (a is set to 1)

#### 6.8.6 Equality and Inequality Operators

The operators `==` and `!=` test for equality and inequality, respectively. They can take operands of any type.

If the operands have *different* types, then `==` returns `0` and `!=` returns `1`.

If the operands have the *same* types, then `==` returns `1` if they are equal to one another, or `0` if not. `!=` returns `0` if they are equal to one another, or `1` if not.

Here are some examples:

    SET a 9 == 7                       (a is set to 0)
    SET a 9 != 7                       (a is set to 1)
    SET a "foo" == 14:33               (a is set to 0)
    SET a "foo" != 14:33               (a is set to 1)

#### 6.8.7 Logical AND

The `&&` operator is a *short-circuit logical AND*. It takes two operands of any type, and works as follows:

- The first operand is evaluated. If it is a *false* value (Section 6.5 on page 42) then that value is returned. The second operand is *not* evaluated in this case.
- Otherwise, the second operand is evaluated and its value is returned as the final value.

Here are some examples:

    SET a 0 && 3                       (a is set to 0)
    SET a "" && 3                      (a is set to "")
    SET a "FOO" && 42                  (a is set to 42)
    SET a 95 && 00:00                  (a is set to 00:00)

#### 6.8.8 Logical OR

The `||` operator is a *short-circuit logical OR*. It takes two operands of any type, and works as follows:

- The first operand is evaluated. If it is a *true* value (Section 6.5 on page 42) then that value is returned. The second operand is *not* evaluated in this case.
- Otherwise, the second operand is evaluated and its value is returned as the final value.

Here are some examples:

    SET a 0 || 3                       (a is set to 3)
    SET a "" || 3                      (a is set to 3)
    SET a "FOO" || 42                  (a is set to "FOO")
    SET a 95 || 00:00                  (a is set to 95)

## 6.9 Built-In Functions

In addition to operators, Remind has many built-in *functions*. To call a function, you simply write the function name followed by `(`, a comma-separated list of arguments, and a closing `)`.

For example, the `max` function can take one or more arguments. They may be of any type (but must all be the same type). It returns the maximum of its arguments. So, for example:

    SET a max(1, 2, 9, 1, 3, -9)       (a is set to 9)
    SET a 5 * max("x", "y")            (a is set to "yyyyy")

Remind has *many* built-in functions (145 as of version 06.02.04) and I’m not going to describe them all in this book. For a comprehensive description of the built-in functions, see the **remind**(1) man page. I’ll describe a few functions in this chapter and a few more in other chapters as I describe other features of Remind.

#### 6.9.1 Some Built-In Functions

Here are a few built-in functions.

**Arithmetic Functions**

- `abs(``n``)` – returns the absolute value of *n* where *n* is of type INT.
- `max(``n1``, n2``, ...)` – returns the maximum value of its arguments. The arguments can be of any type, but must all be the same type.
- `min(``n1``, n2``, ...)` – returns the minimum value of its arguments. The arguments can be of any type, but must all be the same type.
- `sgn(``n``)` – returns `1`, `0` or `-1` if the INT argument *n* is greater than, equal to, or less than zero, respectively.

**String Functions**

- `asc(``str``)` – returns the value of the first byte in the STRING *str* (an INT ranging from `1` to `255`, or `0` if *str* is the empty string.)

- `char(``n``)` – returns a single-byte string consisting of the byte *n*. *n* must be an INT from `0` to `255`; if *n* is `0` then the empty string is returned.

- `codepoint(``str``)` – returns the UNICODE code-point of the first character in the STRING *str*. It is the character-oriented counterpart of `asc`. Whereas `asc` treats its argument as a string of bytes, `codepoint` treats it as a string of characters in the current locale.

- `index(``haystack``, needle [, start``])` – Returns the 1-based byte index where the STRING *needle* appears in the STRING *haystack*, or `0` if *needle* is not found. If the optional INT argument *start* is provided, then the search starts from that byte index.

  Here are some examples:

      SET a index("babble", "bb")        (a is set to 3)
      SET a index("babble", "bob")       (a is set to 0)
      SET a index("abcabcabc", "a")      (a is set to 1)
      SET a index("abcabcabc", "a", 2)   (a is set to 4)

- `mbchar(``n``)` – returns a string that contains the (possibly multi-byte) UNICODE character whose code-point is the INT *n*. It is the character-oriented counterpart of `char`.

  Here are some examples:

      SET a mbchar(128578)              (a is set to "  ")
      SET a char(240) + char(159) + \

      char(153) + char(130)       (a is set to "  ")

  The second example assumes the locale is UTF-8 and it shows that the UTF-8 representation of is 4 bytes long.

- `mbindex(``haystack``, needle [, start``])` – This is the character-oriented counterpart to `index` (which is byte-oriented).

- `strlen(``str``)` – returns the length *in bytes* of the string *str*.

- `mbstrlen(``str``)` – returns the length *in characters* of the string *str*.

- `substr(``str``, start [, end]``)` – Returns a STRING consisting of all the bytes in *str* starting from *start* (a 1-based offset) up to and including *end*. If *end* is omitted, then it defaults to the length of *str*. Both *start* and *end* must be of type INT.

- `mbsubstr(``str``, start [, end]``)` – Returns a STRING consisting of all the characters in *str* starting from *start* (a 1-based offset) up to and including *end*. If *end* is omitted, then it defaults to the length of *str*. Both *start* and *end* must be of type INT.

- `ord(``n``)` – returns a STRING representing the ordinal number corresponding to the INT *n*. Here are some examples:

      SET a ord(1)                      (a is set to "1st")
      SET a ord(4)                      (a is set to "4th")
      SET a ord(13)                     (a is set to "13th")
      SET a ord(23)                     (a is set to "23rd")

- `pad(``src``, padstr``, len [, right``])` – Converts the *src* argument to a STRING (if necessary). If it is shorter than *len* bytes, then it is padded on the left with copies of *padstr* (possibly including a partial copy) until it is exactly *len* bytes long. If the optional *right* argument is supplied and non-zero, then padding is done on the right instead of the left.

- `mbpad(``src``, padstr``, len [, right``])` – This is the character-oriented counterpart to `pad`.

- `plural(``num [, str1 [, str2``]])` – Takes from 1 to 3 arguments. If one argument is supplied, returns `"s"` if *num* is not `1`, and `""` if *num* is `1`.

  If two arguments are supplied, returns *str1* if *num* is *1* or *str1* + `"s"` if *num* is not *1*. If three arguments are supplied, returns *str1* if *num* is `1` and *str2* otherwise.

**Date and Time Functions**

- `today()` – Returns the effective date (Section 2.11 on page 19) as a DATE object.
- `now()` – Returns the effective time (Section 2.11 on page 19) as a TIME object.
- `current()` – Returns the effective date and time as a DATETIME object.
- `realtoday()` – Returns the system date (Section 2.11 on page 19) as a DATE object.
- `realnow()` – Returns the system time (Section 2.11 on page 19) as a TIME object.
- `realcurrent()` – Returns the system date and time as a DATETIME object.
- `isomitted(``x``)` – Given a DATE or DATETIME *x*, returns 1 if (the date part of) *x* is in the global OMIT context, or 0 if it is not.
- `day(``x``)` – Given a DATE or DATETIME *x*, returns the day of the month component (as an INT).
- `wkdaynum(``x``)` – Given a DATE or DATETIME *x*, returns the day of the week, where 0 is Sunday, 1 is Monday, and so on until 6 which is Saturday.
- `monnum(``x``)` – Given a DATE or DATETIME *x*, returns the month number from 1 to 12.
- `year(``x``)` – Given a DATE or DATETIME *x*, returns the year (as an INT).
- `mon(``x``)` – Given a DATE or DATETIME *x*, returns a STRING that is the English name of the month.
- `hour(``x``)` – Given a TIME or DATETIME *x*, returns the hour (as an INT from 0 to 23).
- `minute(``x``)` – Given a TIME or DATETIME *x*, returns the minute (as an INT from 0 to 59).
- `weekno(``date``)` – Given a DATE *date*, returns the ISO 8601 week number of the given *date*. `weekno` can take additional arguments; consult the **remind**(1) man page for more details.

**Logical Functions**

- `choose(``n``, arg1 [, arg2 ...])` – Takes at least two arguments. If *n* is less than `1`, then *arg1* is returned. Otherwise, the *n*th subsequent argument is returned. If *n* is greater than the number of subsequent arguments, then the last argument is returned.

  Note that `choose` only evaluates *n* and whichever argument it actually returns; all other arguments are not evaluated at all.

- `iif(``test1``, arg1 [, test2``, arg2``, ...], default``)` – takes at least three arguments and must have an odd number of arguments. The function operates as follows:
  1.  *test1* is evaluated. If it is true, then *arg1* is returned.
  2.  Otherwise, *test2* (if present) is evaluated and if it is true, *arg2* is returned.
  3.  This continues for all of the *testN* arguments. If none of the tests evaluates to true, then the final argument *default* is returned.

Note that `iif` evaluates only those arguments that are needed to compute a final value. Any arguments that are not needed are not evaluated.

- `catch(``arg1``, arg2``)` – evaluates *arg1* and if no error occurs, returns the resulting value. Otherwise, evaluates *arg2* and returns it.

  `catch` can be useful for using a default value if a variable is not set. For example:

      SET b catch(a, 42)

  If `a` is defined, then `b` will be set to the value of `a`. Otherwise, `catch` suppresses the usual “Undefined variable” error and returns `42` (which is then assigned to `b`.)

## 6.10 User-Defined Functions

In addition to built-in functions, Remind lets you define your own user-defined functions, using the `FSET` command. The FSET command looks something like this:

    FSET name(arg1, arg2, ...) expression

Auser-defined function may take zero or more arguments, which have the same syntax as variable names. When a user-defined function is evaluated, any reference to an argument in *expression* will refer to the function argument rather than a global variable.

Here are some examples of user-defined functions:

    FSET constant_function() 98
    SET a constant_function()          (a is set to 98)

    FSET sumsq(x, y) x*x + y*y
    SET a sumsq(3, 4)                  (a is set to 25)

    FSET weirdo(x) a * x
    SET a weirdo(2)                    (a is set to 50)

In the second example, `x` and `y` refer to function arguments rather than global variables.

In the last example, the `a` in the expression `a * x` refers to the *global variable* `a`, because there is no `a` in the list of function arguments.

#### 6.10.1 Redefining a Function

Remind normally issues a warning if you redefine a user-defined function. You can suppress the warning by putting a `-` between the `FSET` and the function definition. For example:

    FSET func(x) x*2
    FSET func(x) x*3                   (Remind issues a warning)
    FSET - func(x) x*4                 (No warning is issued)

## 6.11 Recursive Functions

It is possible to write recursive functions, though rarely useful. Consider the following example:

    FSET sum_to(n) iif(n <= 0, 0, n + sum_to(n-1))

Because `iif` only evaluates *one* of the second or third arguments, this recursive function will eventually terminate when called with a positive integer value *n* because the termination condition `n <= 0` will eventually be hit.

However, Remind limits the number of recursive calls to 1000 and this is a hard limit. Consider these examples:

    FSET sum_to(n) iif(n <= 0, 0, n + sum_to(n-1))
    SET a sum_to(400)                  (a is set to 80200)
    SET a sum_to(3000)                 (error and a is not changed)

The final `SET` command yields the error “Too many recursive function calls” and does not change the value of `a`.

## 6.12 Commands for Manipulating Variables and Functions

#### 6.12.1 Unsetting a Variable

We’ve seen how the `SET` command can be used to store a value into a variable. If you want to unset a variable so it holds no value, use the `UNSET` command, which takes a list of variable names. Here is an example:

    UNSET a b c

After the command executes, the variables `a`, `b` and `c` will be unset and will hold no values.

#### 6.12.2 Saving and Restoring Variables

If you have a section of a Remind script where you want to set some variables, but not have the changes “leak out” to other parts of the script, you can use `PUSH-VARS` and `POP-VARS` to isolate the scope of the changes. Here is an example:

    PUSH-VARS a b c
    # Code that sets and uses a, b and c
    POP-VARS

After the `POP-VARS` command executes, the variables `a`, `b` and `c` will have the same values they did at the time `PUSH-VARS` was executed. If any of them was unset at the time of `PUSH-VARS`, then it will be unset after the corresponding `POP-VARS`.

#### 6.12.3 Unsetting a Function

If you wish to undefine or unset a function, use the `FUNSET` command. Here is an example:

    FUNSET func1 foo cabbage

After the execution of that command, the functions `func1`, `foo` and `cabbage` will not be defined.

#### 6.12.4 Saving and Restoring Functions

Just as with variables, you may wish to define helper functions for a block of reminders without letting those definitions leak out into surrounding parts of the file and without permanently destroying any previous definitions the functions may have had. The commands `PUSH-FUNCS` and `POP-FUNCS` do the work:

    PUSH-FUNCS foo cabbage
    FSET foo(x) x*2
    FSET cabbage(x, y) x*3 + y*5
    # Use the functions here...

    POP-FUNCS
    # Now foo and cabbage have the same definitions they had
    # just prior to PUSH-FUNCS.  If they were not defined prior
    # to PUSH-FUNCS, then they will no longer be defined here.

## 6.13 Expressions and Reminders

“Expressions are cool,” I hear you say, “but Remind is supposed to be a calendar program. How on Earth does any of this stuff help with scheduling?”

The answer is a Remind feature called *expression pasting*.

The way Remind parses a script is as follows: First, it reads an entire line from the script (this may consist of multiple physical lines if you use line continuation.)

Next, it parses the line character-by-character and does the normal lexical analysis to build up tokens and then grammatical parsing that you’d expect from any interpreter. However, the routine that feeds the parser characters has a special feature: Whenever it encounters text of the form `[``expr``]` where *expr* is a Remind expression, it evaluates *expr*, converts the result to a string, and *replaces* the entire `[``expr``]` text with that string. Then it feeds the parser characters from the result. So compare the following two lines:

    REM 2026-07-01 MSG July 1st!
    REM ['2026-07-08' - 7] MSG July [ord(1)]!

In the second example, the text `['2026-07-08' - 7]` is *replaced* by the result of the expression (which happens to be `2026-07-01`) and the text `[ord(1)]` is replaced by `1st`, which is the result of evaluating `ord(1)`.

The Remind parser has *no idea* that anything nefarious happened and it sees the two lines as identical.

Now, you might think, “That’s cool. But also pointless.” and given what I’ve shown you so far, you’d be right. However, have a look at this:

    REM [easterdate(today())] +7 MSG %"Easter Sunday%" is %b.

The function `easterdate` computes the date of Easter Sunday that falls on or after its argument. If you run the above snippet on April 1st, 2026, the result will be:

    Easter Sunday is in 4 days' time.

This is a *far* more convenient way of calculating Easter than trying to do it by hand. Remind has many built-in functions for more complex date calculations, and expression-pasting is invaluable for solving complex problems.

In the next chapter, we will look at the SATISFY keyword, that lets you solve some very tricky recurrence problems using expressions.
