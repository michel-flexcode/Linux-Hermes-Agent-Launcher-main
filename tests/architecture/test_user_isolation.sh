#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SERVICE="$ROOT/scripts/llama-ornith-serve.sh"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

rg -q 'LLM_USER="\$\{LLM_USER:-llmuser\}"' "$SERVICE" \
  || fail 'The service default user is not llmuser.'
rg -q 'echo "User=\$LLM_USER"' "$SERVICE" \
  || fail 'The systemd unit is not generated with the configured service user.'
rg -q 'echo "Group=\$LLM_USER"' "$SERVICE" \
  || fail 'The systemd unit is not generated with the configured service group.'
! rg -q 'User=ollama|LLM_USER=.*ollama' "$SERVICE" \
  || fail 'The old ollama service user is still configured.'

printf 'PASS: llmuser owns the LLM service configuration.\n'
