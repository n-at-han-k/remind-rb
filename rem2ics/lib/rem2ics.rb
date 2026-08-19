# frozen_string_literal: true

require_relative "rem2ics/cli"
require_relative "rem2ics/converter"
require_relative "rem2ics/event"
require_relative "rem2ics/recurrence"
require_relative "rem2ics/version"

# Reminder files to iCalendar.
#
# This is a port of Martin Michel's remmy.pl, and the interesting difference
# is not that it is Ruby. remmy.pl read the reminder language with regular
# expressions -- as every converter before it did -- and got some of it right.
# There is a lot of that language: eighteen worked examples in Remind's manual
# before the exceptions start, weekday-and-day triggers that are not what they
# look like, SKIP and OMIT and SCANFROM and BEFORE and AFTER.
#
# rem2ics does not read it at all. It is built on the remind-rb bindings, so
# Remind parses the trigger, Remind computes the dates it fires on, and Remind
# renders the message. What is left for this side is the mapping to
# iCalendar's vocabulary, and one judgement:
#
#   A recurring reminder becomes an event with an RRULE -- but only when that
#   RRULE has been expanded and checked, occurrence by occurrence, against the
#   dates Remind gives. Where the two agree the calendar recurs forever and
#   correctly. Where they disagree -- a reminder that skips holidays, one that
#   moves off weekends -- the event carries Remind's own dates instead.
#
# So the output is never wrong about when something happens; at worst it is
# finite where the reminder is not.
module Rem2ics
end
