/***************************************************************/
/*                                                             */
/*  SHIM.C                                                     */
/*                                                             */
/*  The one piece of C in remind-rb.                           */
/*                                                             */
/*  Remind's C interface is not hostile to a binding, but two  */
/*  parts of it cannot be reached from Fiddle alone:           */
/*                                                             */
/*  1. Struct layout. Trigger has thirty-odd fields, and       */
/*     reading them from Ruby would mean hard-coding byte      */
/*     offsets that the next release, the next compiler or the */
/*     next platform is free to move. The accessors below are  */
/*     compiled against the same headers as the rest of the    */
/*     library, so the offsets are the compiler's problem      */
/*     rather than the binding's.                              */
/*                                                             */
/*  2. The sequence in DoRem. Parsing a REM line means         */
/*     CreateParser, ParseRem, ComputeTrigger, ParseToken,     */
/*     FindToken and DoSubst in that order, with cleanup on    */
/*     every early exit. Driving that from Ruby would mean     */
/*     six FFI calls per line and a Parser struct allocated by */
/*     size; here it is one call that either works or does     */
/*     not.                                                    */
/*                                                             */
/*  Everything else -- dates, the moon, the Hebrew calendar,   */
/*  expression evaluation -- is called directly from Ruby, and */
/*  deliberately not wrapped here.                             */
/*                                                             */
/*  This file is part of remind-rb, and is distributed under   */
/*  the same terms as Remind itself.                           */
/*  SPDX-License-Identifier: GPL-2.0-only                      */
/*                                                             */
/***************************************************************/

#include "config.h"

#include <stddef.h>
#include <string.h>

#include "types.h"
#include "protos.h"
#include "globals.h"
#include "err.h"

/* How big the caller has to make the blocks it hands back in. */
size_t remrb_sizeof_trigger(void)  { return sizeof(Trigger); }
size_t remrb_sizeof_timetrig(void) { return sizeof(TimeTrig); }

/* The sentinels Remind uses for "the reminder did not say". */
int remrb_no_day(void)      { return NO_DAY; }
int remrb_no_month(void)    { return NO_MON; }
int remrb_no_year(void)     { return NO_YR; }
int remrb_no_weekday(void)  { return NO_WD; }
int remrb_no_until(void)    { return NO_UNTIL; }
int remrb_no_time(void)     { return NO_TIME; }

/* The marker DoSubst leaves around the part of a message that %" marked as
   the calendar entry's title. */
int remrb_quote_marker(void) { return QUOTE_MARKER; }

/* The two ways DoSubst renders a message. */
int remrb_normal_mode(void) { return NORMAL_MODE; }
int remrb_cal_mode(void)    { return CAL_MODE; }

/* The body types, so Ruby can tell a MSG from a RUN without repeating the
   numbers. */
int remrb_msg_type(void)      { return MSG_TYPE; }
int remrb_msf_type(void)      { return MSF_TYPE; }
int remrb_run_type(void)      { return RUN_TYPE; }
int remrb_cal_type(void)      { return CAL_TYPE; }
int remrb_sat_type(void)      { return SAT_TYPE; }
int remrb_passthru_type(void) { return PASSTHRU_TYPE; }

/* Trigger accessors.  One line each, and each one is the compiler's opinion
   of where the field is rather than the binding's. */
#define TRIGGER_READER(field) \
    int remrb_trigger_##field(Trigger const *t) { return t->field; }

TRIGGER_READER(wd)              /* bit set: 1 << 0 is Monday, as Remind counts */
TRIGGER_READER(d)               /* day of month, or NO_DAY */
TRIGGER_READER(m)               /* month, 0-based, or NO_MON */
TRIGGER_READER(y)               /* year, or NO_YR */
TRIGGER_READER(back)            /* the count on a --n / -n delta */
TRIGGER_READER(delta)           /* advance warning, in days */
TRIGGER_READER(rep)             /* *n repeat interval, in days */
TRIGGER_READER(localomit)       /* bit set of weekdays this reminder OMITs */
TRIGGER_READER(skip)            /* SKIP / BEFORE / AFTER */
TRIGGER_READER(until)           /* UNTIL / THROUGH date, or NO_UNTIL */
TRIGGER_READER(typ)             /* MSG_TYPE, RUN_TYPE, ... */
TRIGGER_READER(once)            /* ONCE */
TRIGGER_READER(scanfrom)        /* SCANFROM / FROM date */
TRIGGER_READER(from)
TRIGGER_READER(priority)        /* PRIORITY */
TRIGGER_READER(duration_days)
TRIGGER_READER(eventduration)   /* DURATION, in minutes */
TRIGGER_READER(eventstart)      /* start as a Remind datetime */
TRIGGER_READER(is_todo)
TRIGGER_READER(addomit)
TRIGGER_READER(need_wkday)

char const *remrb_trigger_tags(Trigger *t)
{
    return DBufValue(&t->tags);
}

char const *remrb_trigger_timezone(Trigger const *t)
{
    return t->tz;
}

/* TimeTrig accessors. */
int remrb_timetrig_time(TimeTrig const *tt)     { return tt->ttime; }
int remrb_timetrig_delta(TimeTrig const *tt)    { return tt->delta; }
int remrb_timetrig_repeat(TimeTrig const *tt)   { return tt->rep; }
int remrb_timetrig_duration(TimeTrig const *tt) { return tt->duration; }

/* The tokens main.c dispatches to something other than DoRem.  Everything
   else -- a number, a month name, a word Remind does not know -- opens a
   reminder, which is Remind's `default:` case.  T_RemType is on the reminder
   side: a line that opens with a bare MSG is a reminder with an empty
   trigger.  T_Omit is not: OMIT can carry a reminder, but the command itself
   is a calendar-wide exclusion rather than an event. */
static int
is_command(enum TokTypes type)
{
    switch (type) {
    case T_Banner:  case T_Clr:        case T_Comment:  case T_Debug:
    case T_Dumpvars:case T_Else:       case T_Empty:    case T_EndIf:
    case T_ErrMsg:  case T_Exit:       case T_Expr:     case T_Flush:
    case T_Frename: case T_Fset:       case T_Funset:   case T_If:
    case T_IfTrig:  case T_Include:    case T_IncludeCmd:
    case T_IncludeR:case T_IncludeSys: case T_Omit:     case T_Pop:
    case T_PopFuncs:case T_PopVars:    case T_Preserve: case T_Push:
    case T_PushFuncs: case T_PushVars: case T_Return:   case T_Set:
    case T_Translate: case T_UnSet:
        return 1;
    default:
        return 0;
    }
}

/* The expanded message from the last successful parse.  One buffer, reused:
   the caller copies the string into Ruby before the next call, and the Ruby
   side serialises calls anyway because Remind's state is process-wide. */
static DynamicBuffer body;
static int body_ready = 0;

static void
reset_body(void)
{
    if (!body_ready) {
        DBufInit(&body);
        body_ready = 1;
    } else {
        DBufFree(&body);
    }
}

/***************************************************************/
/*                                                             */
/*  remrb_parse_reminder                                       */
/*                                                             */
/*  Parse one REM line the way DoRem does, minus the parts a   */
/*  calendar has no use for: no queueing, no SATISFY, no purge */
/*  mode, no output.                                           */
/*                                                             */
/*  Fills in the caller's Trigger and TimeTrig, writes the     */
/*  first date the reminder triggers on to *dse, and points    */
/*  *msg at the message with its %-substitutions expanded for  */
/*  that date.  Answers OK, or the error code Remind raised;   */
/*  the caller frees the Trigger either way.                   */
/*                                                             */
/***************************************************************/
int
remrb_parse_reminder(char const *line, Trigger *trig, TimeTrig *tim,
                     int *dse, char const **msg, int mode)
{
    Parser p;
    DynamicBuffer token_buf;
    Token tok;
    int r;

    reset_body();
    DBufInit(&token_buf);
    *dse = -1;
    *msg = NULL;

    CreateParser(line, &p);

    /* Mirror how main.c decides what a line is. It reads the first token and
       dispatches on it: T_Rem is a reminder, T_RemType (a bare MSG or CAL) is
       a reminder, an unrecognised word is a reminder by default -- and
       anything else is one of Remind's other commands, which is not an event
       and must not be parsed as though it were.

       ParseRem starts at the date specification, after the keyword, which is
       why REM is consumed and everything else is pushed back. */
    r = ParseToken(&p, &token_buf);
    if (r != OK) {
        DestroyParser(&p);
        return r;
    }
    FindToken(DBufValue(&token_buf), &tok);

    if (tok.type != T_Rem) {
        if (is_command(tok.type)) {
            DBufFree(&token_buf);
            DestroyParser(&p);
            return E_PARSE_ERR;
        }
        r = PushToken(DBufValue(&token_buf), &p);
        if (r != OK) {
            DBufFree(&token_buf);
            DestroyParser(&p);
            return r;
        }
    }
    DBufFree(&token_buf);

    r = ParseRem(&p, trig, tim);
    if (r != OK) {
        DestroyParser(&p);
        return r;
    }

    /* SATISFY is a control construct, not a calendar entry, and the rest of
       DoRem's handling of it is about the reminder queue. */
    if (trig->typ == SAT_TYPE) {
        DestroyParser(&p);
        return E_PARSE_ERR;
    }

    *dse = ComputeTrigger(get_scanfrom(trig), trig, tim, &r, 1);
    if (r != OK) {
        DestroyParser(&p);
        return r;
    }
    *dse = AdjustTriggerForTimeZone(trig, *dse, tim, 0);

    /* ParseRem has already read the keyword that opens the body -- MSG, MSF,
       RUN, CAL, SPECIAL -- and left trig->typ set to it, which is why DoRem
       goes straight from here to rendering. A line with no body at all leaves
       it at NO_TYPE. */
    if (trig->typ == NO_TYPE) {
        DestroyParser(&p);
        return E_EOLN;
    }

    /* NORMAL_MODE renders the message the way `remind` prints it; CAL_MODE
       renders it the way a calendar entry wants it, which is where a %"..%"
       title is honoured. The caller picks, because a calendar entry needs
       both: one for the summary and one for the description. */
    r = DoSubst(&p, &body, trig, tim, *dse, mode);
    DestroyParser(&p);

    if (r != OK) {
        return r;
    }

    *msg = DBufValue(&body);
    return OK;
}

/***************************************************************/
/*                                                             */
/*  remrb_next_trigger                                         */
/*                                                             */
/*  The next date this reminder triggers on, at or after       */
/*  `from`.  This is the same call DoRem makes to find the     */
/*  first one, run again from further along, which is how      */
/*  Remind itself walks a reminder across a date range.        */
/*                                                             */
/*  It exists because a calendar has to decide whether an      */
/*  RRULE says what the reminder says, and the only authority  */
/*  on that is the reminder: generate a rule, expand it, and   */
/*  compare it against these dates.  save_in_globals is 0 --   */
/*  walking a reminder must not move Remind's idea of the last */
/*  trigger.                                                   */
/*                                                             */
/*  Answers -1 and sets *err when the reminder has no further  */
/*  trigger date, which is how a run-out or expired reminder   */
/*  ends a walk.                                               */
/*                                                             */
/***************************************************************/
int
remrb_next_trigger(Trigger *trig, TimeTrig *tim, int from, int *err)
{
    int dse;

    *err = OK;
    dse = ComputeTrigger(from, trig, tim, err, 0);
    if (*err != OK) {
        return -1;
    }
    return dse;
}

/***************************************************************/
/*                                                             */
/*  remrb_open_file / remrb_read_line                          */
/*                                                             */
/*  Remind's own file reader.  A reminder file is not a list of */
/*  lines: a backslash continues one, INCLUDE pulls another     */
/*  file into the middle of it, and both are handled here       */
/*  rather than in the caller.  ReadLine leaves the logical     */
/*  line in the CurLine global and pops back out of an included */
/*  file when it ends.                                         */
/*                                                             */
/*  remrb_read_line answers OK, or E_EOF when there is nothing  */
/*  left in any open file.                                     */
/*                                                             */
/***************************************************************/
int
remrb_open_file(char const *path)
{
    return IncludeFile(path);
}

/* INCLUDE is a command, not part of the reader: ReadLine pops back out of an
   included file when it ends, but something has to push one on in the first
   place, and in `remind` that something is DoCommand.  This is that, for the
   three forms that name a file.

   INCLUDECMD is deliberately not among them.  It runs a shell command and
   reads its output as reminders, and a program that converts somebody else's
   reminder file should not execute what is in it. */
static int
follow_include(char const *line)
{
    Parser p;
    DynamicBuffer buf;
    Token tok;
    int handled = 0;

    CreateParser(line, &p);
    DBufInit(&buf);

    if (ParseToken(&p, &buf) == OK) {
        FindToken(DBufValue(&buf), &tok);
        if (tok.type == T_Include ||
            tok.type == T_IncludeR ||
            tok.type == T_IncludeSys) {
            (void) DoInclude(&p, tok.type);
            handled = 1;
        }
    }

    DBufFree(&buf);
    DestroyParser(&p);
    return handled;
}

int
remrb_read_line(char const **text)
{
    int r;

    while (1) {
        r = ReadLine();
        if (r != OK) {
            *text = NULL;
            return r;
        }
        if (!follow_include(CurLine)) {
            *text = CurLine;
            return r;
        }
    }
}

int remrb_eof(void) { return E_EOF; }

/* ParseRem allocates: the tag buffer, the time zone, the INFO headers. */
void
remrb_free_trigger(Trigger *t)
{
    FreeTrig(t);
}
