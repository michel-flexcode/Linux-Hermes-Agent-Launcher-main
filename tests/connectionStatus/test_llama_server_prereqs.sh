#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ENV_FILE="$ROOT/config/.env.example"
SCRIPT="$ROOT/scripts/llama-ornith-serve.sh"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

# The environment file must define the runtime prerequisites used by llama-server.
for key in MODEL_DIR LOGDIR LISTEN_HOST LISTEN_PORT LLM_USER CTX_SIZE MODEL_FILENAME; do
  rg -q "^${key}=" "$ENV_FILE" || fail "Missing environment key: $key"
done

rg -q '^LLM_USER=llmuser$' "$ENV_FILE" || fail 'LLM_USER must default to llmuser.'
rg -q '^LISTEN_HOST=0\.0\.0\.0$' "$ENV_FILE" || fail 'LISTEN_HOST must bind to all interfaces.'
rg -q '^LISTEN_PORT=8080$' "$ENV_FILE" || fail 'LISTEN_PORT must default to 8080.'
rg -q '^CTX_SIZE=73728$' "$ENV_FILE" || fail 'CTX_SIZE must remain 73728 for the Hermes requirement.'
rg -q '^MODEL_FILENAME=.*Q4_K_M\.gguf$' "$ENV_FILE" || fail 'MODEL_FILENAME must point to a Q4_K_M GGUF model.'

# The server script must require a real llama-server binary and a model path.
rg -q 'llama-server introuvable' "$SCRIPT" || fail 'Server script must explicitly fail without llama-server.'
rg -q 'MODEL_DIR/\$MODEL_BASENAME|--model \$MODEL_DIR/\$MODEL_BASENAME' "$SCRIPT" || fail 'Server script must reference the model path.'
rg -q '0\.0\.0\.0|--host \$LISTEN_HOST|--port \$LISTEN_PORT' "$SCRIPT" || fail 'Server must bind to the configured host and port.'

printf 'PASS: llama.cpp runtime prerequisites and server binding are defined.\n'
