#!/bin/sh
[ -n "$FAKE_STDOUT" ] && printf '%s' "$FAKE_STDOUT"
[ -n "$FAKE_STDERR" ] && printf '%s' "$FAKE_STDERR" >&2
[ -n "$FAKE_SIGNAL" ] && kill -"$FAKE_SIGNAL" $$
exit "${FAKE_EXIT:-0}"
