#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$ROOT/scripts/bootstrap-systemd.sh"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

if [[ ! -f "$SCRIPT" ]]; then
  fail 'Systemd bootstrap script is missing.'
fi

rg -q 'systemctl daemon-reload' "$SCRIPT" || fail 'Script must reload systemd units.'
rg -q 'systemctl enable --now llama-ornith.service' "$SCRIPT" || fail 'Script must enable and start the unit.'
rg -q 'systemctl is-active --quiet llama-ornith.service' "$SCRIPT" || fail 'Script must validate service activation.'
grep -Eq 'ExecStart=|llama-server|--model .*MODEL_FILENAME' "$SCRIPT" || fail 'Script must generate a valid llama-server ExecStart command.'

printf 'PASS: systemd bootstrap script installs and validates the backend service.\n'
