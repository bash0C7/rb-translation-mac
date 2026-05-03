#!/bin/sh
# Fake helper for HelperClient tests. Behavior driven by env vars:
#   FAKE_STDOUT — printed to stdout (no trailing newline)
#   FAKE_STDERR — printed to stderr (no trailing newline)
#   FAKE_EXIT   — exit code (default 0)
#   FAKE_SIGNAL — if set (e.g. KILL, TERM), self-signal so the caller observes
#                 a Process::Status with exitstatus == nil
[ -n "$FAKE_STDOUT" ] && printf '%s' "$FAKE_STDOUT"
[ -n "$FAKE_STDERR" ] && printf '%s' "$FAKE_STDERR" >&2
[ -n "$FAKE_SIGNAL" ] && kill -"$FAKE_SIGNAL" $$
exit "${FAKE_EXIT:-0}"
