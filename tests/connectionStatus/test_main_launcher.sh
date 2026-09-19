#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LAUNCHER="$ROOT/launch.sh"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

help_output="$($LAUNCHER help)"
for command in menu setup bootstrap systemd install start stop restart status models api internet reconnect watchdog tests; do
  printf '%s\n' "$help_output" | rg -q "^[[:space:]]+$command[[:space:]]" \
    || fail "Missing launcher command in help: $command"
done

if "$LAUNCHER" unknown-command >/tmp/linux-hermes-launcher-test.err 2>&1; then
  fail 'Unknown launcher commands must return a non-zero status.'
fi

rg -q 'Unknown command:' /tmp/linux-hermes-launcher-test.err \
  || fail 'Unknown launcher command does not produce a clear error.'

rm -f /tmp/linux-hermes-launcher-test.err
printf 'PASS: launch.sh exposes documented commands and rejects unknown commands.\n'
