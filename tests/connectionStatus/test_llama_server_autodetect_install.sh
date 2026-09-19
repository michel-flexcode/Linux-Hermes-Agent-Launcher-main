#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HELPER="$ROOT/scripts/ensure-llama-server.sh"
SERVE_SCRIPT="$ROOT/scripts/llama-ornith-serve.sh"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

[[ -f "$HELPER" ]] || fail 'Auto-detect/install helper is missing.'
rg -q 'llama-server' "$HELPER" || fail 'Helper must reference llama-server.'
rg -q 'command -v.*llama-server|/usr/local/bin/llama-server|/usr/bin/llama-server' "$HELPER" || fail 'Helper must detect llama-server on PATH or common install paths.'
rg -q 'git clone|make -j|cmake' "$HELPER" || fail 'Helper must include an installation path using source build tools.'
rg -q 'ensure_bin|LLAMA_BIN' "$SERVE_SCRIPT" || fail 'Serve script must use the shared llama-server detection.'

printf 'PASS: auto-detect/install flow exists for llama-server.\n'
