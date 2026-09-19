#!/usr/bin/env bash
# ============================================================================
# test_quickstart_command.sh
#
# Static regression test for the `./launch.sh quickstart` one-liner: it must
# check/install system dependencies first, then chain setup, bootstrap,
# model, install and api in order.
# ============================================================================
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LAUNCHER="$ROOT/launch.sh"
DEPS_SCRIPT="$ROOT/scripts/check-system-deps.sh"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

[[ -f "$DEPS_SCRIPT" ]] || fail 'scripts/check-system-deps.sh is missing.'
[[ -x "$DEPS_SCRIPT" ]] || fail 'scripts/check-system-deps.sh must be executable.'

help_output="$("$LAUNCHER" help)"
printf '%s\n' "$help_output" | rg -q '^[[:space:]]+quickstart[[:space:]]' \
  || fail 'launch.sh help does not document the quickstart command.'

rg -q 'quickstart\)' "$LAUNCHER" || fail 'launch.sh is missing the quickstart case branch.'
rg -Fq '"$SCRIPTS/check-system-deps.sh"' "$LAUNCHER" || fail 'quickstart must run check-system-deps.sh first.'

for step in setup bootstrap model install api; do
  rg -Fq "\"\$ROOT/launch.sh\" $step" "$LAUNCHER" \
    || fail "quickstart does not chain the '$step' step."
done

# check-system-deps.sh must only try to install with apt when it has root or sudo.
rg -q 'has_sudo\(\)' "$DEPS_SCRIPT" || fail 'check-system-deps.sh must detect sudo availability.'
rg -q 'is_root\(\)' "$DEPS_SCRIPT" || fail 'check-system-deps.sh must detect root execution.'
rg -q 'apt-get install' "$DEPS_SCRIPT" || fail 'check-system-deps.sh must be able to install missing packages via apt-get.'

printf 'PASS: quickstart checks/installs system deps then chains setup, bootstrap, model, install and api.\n'
