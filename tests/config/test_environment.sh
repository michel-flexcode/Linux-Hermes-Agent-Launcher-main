#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ENV_FILE="$ROOT/config/.env.example"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
required=(LLM_USER MODEL_DIR LOGDIR LISTEN_HOST LISTEN_PORT CTX_SIZE MODEL_FILENAME)
for key in "${required[@]}"; do
  rg -q "^${key}=" "$ENV_FILE" || fail "Missing configuration key: $key"
done

rg -q '^LLM_USER=llmuser$' "$ENV_FILE" || fail 'LLM_USER must default to llmuser.'
rg -q '^CTX_SIZE=73728$' "$ENV_FILE" || fail 'CTX_SIZE must remain 73728.'
rg -q '^MODEL_FILENAME=.*Q4_K_M\.gguf$' "$ENV_FILE" || fail 'The configured model must be Q4_K_M GGUF.'

printf 'PASS: environment defaults are complete and aligned with llmuser.\n'
