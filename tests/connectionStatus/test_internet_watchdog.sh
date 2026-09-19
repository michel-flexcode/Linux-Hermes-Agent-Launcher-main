#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WATCHDOG="$ROOT/scripts/internet-watchdog.sh"
ENV_FILE="$ROOT/config/.env.example"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

rg -q 'INTERNET_CHECK_URL' "$ENV_FILE" || fail 'Internet check URL is not configurable.'
rg -q 'INTERNET_CHECK_INTERVAL' "$ENV_FILE" || fail 'Internet check interval is not configurable.'
rg -q 'curl .*--connect-timeout' "$WATCHDOG" || fail 'Watchdog has no bounded Internet check.'
rg -q 'nmcli networking on' "$WATCHDOG" || fail 'Watchdog does not enable NetworkManager networking.'
rg -q 'nmcli device connect' "$WATCHDOG" || fail 'Watchdog does not request device reconnection.'
rg -q 'Restart=always' "$WATCHDOG" || fail 'Watchdog unit is not configured to restart.'
rg -q 'hermes-internet-watchdog\.service' "$WATCHDOG" || fail 'Watchdog unit name is missing.'
! rg -q 'User=llmuser|Group=llmuser' "$WATCHDOG" \
	|| fail 'The network watchdog must not be coupled to the LLM service user.'

printf 'PASS: Internet watchdog is configured for checks and reconnection.\n'
