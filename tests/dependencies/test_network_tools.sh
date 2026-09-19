#!/usr/bin/env bash
# ============================================================================
# test_network_tools.sh
#
# Verifies the network tooling used by scripts/api-validate.sh and
# scripts/internet-watchdog.sh. curl is a hard requirement (both scripts fail
# without it); nmcli/NetworkManager is only used to attempt an automatic
# reconnection and already degrades gracefully in code, so it is reported
# here without failing the suite.
# ============================================================================
set -uo pipefail

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
warn() { printf 'WARN: %s\n' "$*"; }

command -v curl >/dev/null 2>&1 \
  || fail 'curl is required by scripts/api-validate.sh and scripts/internet-watchdog.sh.'

if command -v nmcli >/dev/null 2>&1; then
  printf 'INFO: nmcli found; automatic NetworkManager reconnection is available.\n'
else
  warn 'nmcli not found; scripts/internet-watchdog.sh will only report connectivity, not reconnect automatically.'
fi

printf 'PASS: curl is available (nmcli availability reported above, non-blocking).\n'
