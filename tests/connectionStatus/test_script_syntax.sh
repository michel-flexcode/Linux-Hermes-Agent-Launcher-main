#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

for script in "$ROOT"/scripts/*.sh; do
  bash -n "$script"
done

bash -n "$ROOT/launch.sh"
[[ -x "$ROOT/launch.sh" ]] || {
  printf 'FAIL: launch.sh is not executable.\n' >&2
  exit 1
}

printf 'PASS: all Bash scripts have valid syntax.\n'
