# frozen_string_literal: true

module Remind
  # <Remind release>.<our release>. The first three segments say which version
  # of Remind this gem vendors and binds; the fourth is ours, bumped for
  # changes on the Ruby side against that same release. Managed by
  # bin/increment-version -- edit that, not this.
  VERSION = "6.2.10.0"

  # The vendored source directory is named for the release, in Remind's own
  # zero-padded spelling.
  REMIND_VERSION = "06.02.10"
end
