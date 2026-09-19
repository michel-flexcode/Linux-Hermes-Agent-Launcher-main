#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CLIENT_SCRIPT="$ROOT/scripts/hermes-client-set.sh"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

rg -q 'providers\.openai_compatible\.base_url' "$CLIENT_SCRIPT" \
  || fail 'The client script does not configure the OpenAI-compatible provider.'
rg -q '/v1' "$CLIENT_SCRIPT" || fail 'The client script does not use the /v1 endpoint.'
! rg -q -i 'q3_k|q3|ollama' "$CLIENT_SCRIPT" \
  || fail 'The client script still exposes Q3 or Ollama configuration.'

printf 'PASS: Hermes client configuration targets the llama.cpp OpenAI API.\n'
