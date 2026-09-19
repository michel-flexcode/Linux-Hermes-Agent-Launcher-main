#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LAUNCHER="$ROOT/launch.sh"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

check_output() {
  local label="$1"
  local file="$2"

  if rg -q 'scripts/scripts|No such file or directory' "$file"; then
    fail "$label triggered the nested scripts path regression."
  fi

  if rg -q 'Permission denied.*hermes-internet-watchdog\.log|/var/log/hermes-internet-watchdog\.log' "$file"; then
    fail "$label must not fail when the log file is not writable."
  fi
}

# Direct command: should report connectivity status without path or log regressions.
output_direct=$(mktemp)
set +e
"$LAUNCHER" internet >"$output_direct" 2>&1
status_direct=$?
set -e
[[ "$status_direct" -eq 0 || "$status_direct" -eq 1 ]] \
  || fail "./launch.sh internet must return 0 or 1, got $status_direct."
check_output 'Direct internet command' "$output_direct"

# Interactive menu path: pressing 7 must not resolve to scripts/scripts.
output_menu=$(mktemp)
set +e
printf '7\n' | "$LAUNCHER" >"$output_menu" 2>&1
status_menu=$?
set -e
[[ "$status_menu" -eq 0 || "$status_menu" -eq 1 ]] \
  || fail "Menu option 7 must return 0 or 1, got $status_menu."
check_output 'Interactive launcher menu' "$output_menu"

printf 'PASS: launcher internet path and logging regressions are covered.\n'
