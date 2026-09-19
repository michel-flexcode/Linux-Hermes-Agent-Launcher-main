#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

if rg -n -i '^[[:space:]]*[^#].*(systemctl[[:space:]]+set-default[[:space:]]+multi-user\.target|sysctl[[:space:]]+-w|grub-mkconfig|GRUB_CMDLINE_LINUX)' "$ROOT/scripts"; then
  fail 'A script still changes the global boot or kernel configuration.'
fi

rg -q 'graphical\.target' "$ROOT/scripts/pre-start-optimizer.sh" \
  || fail 'The optimizer does not document the graphical boot target.'

printf 'PASS: scripts do not change the global boot or kernel configuration.\n'
