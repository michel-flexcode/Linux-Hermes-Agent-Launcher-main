#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

if rg -n -i 'q3_k|q3|ollama' "$ROOT/config" "$ROOT/scripts"; then
  fail 'A degraded Q3 or Ollama path is still present in deployment code.'
fi

rg -q 'Q4_K_M' "$ROOT/config/.env.example" \
  || fail 'The configuration does not select Q4_K_M.'

printf 'PASS: deployment code has no degraded Q3 or Ollama path.\n'
