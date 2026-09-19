#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LAUNCHER="$ROOT/launch.sh"
BOOTSTRAP="$ROOT/scripts/bootstrap-config.sh"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

"$LAUNCHER" help | rg -q '^[[:space:]]+bootstrap[[:space:]]' \
  || fail 'Missing bootstrap command in launcher help.'

if [[ ! -f "$BOOTSTRAP" ]]; then
  fail 'Bootstrap config script is missing.'
fi

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT
mkdir -p "$tmpdir/models"
cp "$ROOT/config/.env.example" "$tmpdir/.env.example"
printf 'fake gguf\n' > "$tmpdir/models/Ornith-1.5-35B-A3B-Q4_K_M.gguf"

"$BOOTSTRAP" --env-file "$tmpdir/.env" --template "$tmpdir/.env.example" --model-dir "$tmpdir/models" >/tmp/linux-hermes-bootstrap.out 2>&1

rg -q '^MODEL_FILENAME=Ornith-1.5-35B-A3B-Q4_K_M\.gguf$' "$tmpdir/.env" \
  || fail 'Bootstrap did not write the expected MODEL_FILENAME.'
rg -q '^MODEL_DIR=' "$tmpdir/.env" || fail 'Bootstrap did not persist MODEL_DIR.'
rg -q '^CTX_SIZE=73728$' "$tmpdir/.env" || fail 'Bootstrap must keep the required CTX_SIZE default.'
rg -q '^LISTEN_PORT=8080$' "$tmpdir/.env" || fail 'Bootstrap must keep LISTEN_PORT default 8080.'

printf 'PASS: bootstrap config normalizes .env values and persist the active GGUF filename.\n'
