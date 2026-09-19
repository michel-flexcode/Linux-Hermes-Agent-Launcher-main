#!/usr/bin/env bash
# ============================================================================
# test_launcher_no_sudo_requirement.sh
#
# Static regression test: the interactive menu and the service scripts must
# not hard-fail when sudo is unavailable. This guards against reintroducing
# blocking checks like `[[ "$(id -u)" -eq 0 ]] || fail ...` on the
# start/stop/status/restart paths.
# ============================================================================
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MENU_SCRIPT="$ROOT/scripts/launcher.sh"
SERVE_SCRIPT="$ROOT/scripts/llama-ornith-serve.sh"
GIGA_SCRIPT="$ROOT/scripts/giga-serve.sh"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

# The interactive menu must no longer force a "Utilise sudo." dead end for
# the service management option.
rg -q 'Utilise sudo\.' "$MENU_SCRIPT" \
  && fail 'launcher.sh must not force sudo before managing the service.'

# llama-ornith-serve.sh must offer a local (non-systemd) fallback and must not
# unconditionally require root for start/status/stop/restart.
rg -q 'start_local\(\)' "$SERVE_SCRIPT" || fail 'llama-ornith-serve.sh is missing the local-mode start function.'
rg -q 'stop_local\(\)' "$SERVE_SCRIPT" || fail 'llama-ornith-serve.sh is missing the local-mode stop function.'
rg -q 'status_local\(\)' "$SERVE_SCRIPT" || fail 'llama-ornith-serve.sh is missing the local-mode status function.'
rg -q 'has_sudo\(\)' "$SERVE_SCRIPT" || fail 'llama-ornith-serve.sh must detect sudo availability instead of assuming it.'
rg -q 'IS_ROOT' "$SERVE_SCRIPT" || fail 'llama-ornith-serve.sh must branch on root vs non-root execution.'

# ensure-llama-server.sh must be able to install without sudo (user-local bin).
rg -q 'install_from_source_local' "$ROOT/scripts/ensure-llama-server.sh" \
  || fail 'ensure-llama-server.sh is missing the no-sudo local install path.'

# giga-serve.sh must route through the local process manager, not only systemctl.
rg -q 'uses_systemd' "$GIGA_SCRIPT" || fail 'giga-serve.sh must detect whether systemd control is actually usable.'
rg -q 'SERVE_SCRIPT' "$GIGA_SCRIPT" || fail 'giga-serve.sh must delegate to llama-ornith-serve.sh when systemd is unavailable.'

printf 'PASS: menu and service scripts expose a no-sudo fallback path.\n'
