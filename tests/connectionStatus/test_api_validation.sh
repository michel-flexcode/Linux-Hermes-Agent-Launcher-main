#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$ROOT/scripts/api-validate.sh"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

if [[ ! -f "$SCRIPT" ]]; then
  fail 'Local API validation script is missing.'
fi

rg -q 'curl .*\/v1\/models' "$SCRIPT" || fail 'Script must call /v1/models.'
rg -q 'curl .*\/v1\/chat\/completions' "$SCRIPT" || fail 'Script must call /v1/chat/completions.'
rg -q 'HTTP .*200|HTTP \$MODELS_CODE|HTTP \$CHAT_CODE' "$SCRIPT" || fail 'Script must validate HTTP 200 status codes.'

printf 'PASS: API validation script covers models and chat completion endpoints.\n'
