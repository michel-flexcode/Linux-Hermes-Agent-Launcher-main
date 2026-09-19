#!/usr/bin/env bash
# ============================================================================
# test_python_runtime.sh
#
# Verifies the Python runtime prerequisites used by scripts/api-validate.sh
# and scripts/download-ornith-model.sh: python3 itself, its stdlib json
# module (JSON parsing of the OpenAI-compatible API), and pip (needed to
# auto-install huggingface_hub on first use).
# ============================================================================
set -uo pipefail

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

command -v python3 >/dev/null 2>&1 \
  || fail 'python3 is required by scripts/api-validate.sh and scripts/download-ornith-model.sh.'

python3 -c 'import json' 2>/dev/null \
  || fail 'The python3 json module is required to parse the OpenAI-compatible API responses.'

python3 -m pip --version >/dev/null 2>&1 \
  || fail 'python3 -m pip is required to auto-install huggingface_hub on first model download.'

printf 'PASS: python3, its json module and pip are available.\n'
