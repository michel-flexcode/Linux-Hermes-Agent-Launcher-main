#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LAUNCHER="$ROOT/launch.sh"
MENU_SCRIPT="$ROOT/scripts/launcher.sh"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

# 1. Verify the CLI dispatcher exposes every documented command.
help_output="$($LAUNCHER help)"
for command in menu setup install start stop restart status models internet reconnect watchdog tests help; do
  printf '%s\n' "$help_output" | rg -q "^[[:space:]]+$command[[:space:]]" \
    || fail "Launcher help is missing command: $command"
done

# 2. Verify each menu option 1..7 is wired to the expected action.
for pattern in \
  '1) Configurer .env + secrets' \
  '2) Optimiser le systeme sans couper le bureau' \
  '3) Gérer le service' \
  '4) Status GPU / API (diagnostic)' \
  '5) Lister les modèles GGUF' \
  '6) Basculer de modèle (switch)' \
  '7) Vérifier la connexion Internet'; do
  rg -Fq -- "$pattern" "$MENU_SCRIPT" || fail "Menu option wiring missing: $pattern"
done

# 3. Check option handlers in the case block.
for pattern in \
  '1) gen_env;;' \
  '2) optimize;;' \
  '3) serve;;' \
  '4) "$BASE/scripts/giga-serve.sh" status;;' \
  '5) "$BASE/scripts/giga-serve.sh" models;;' \
  '7) "$BASE/scripts/internet-watchdog.sh" check;;'; do
  rg -Fq -- "$pattern" "$MENU_SCRIPT" || fail "Menu handler missing: $pattern"
done

# 3. Verify the top-level launcher routes all command aliases to the correct scripts.
for pattern in \
  'menu)' \
  'setup)' \
  'install)' \
  'start|stop|restart|status)' \
  'models)' \
  'internet)' \
  'reconnect)' \
  'watchdog)' \
  'tests)' \
  'help|-h|--help)'; do
  rg -Fq -- "$pattern" "$LAUNCHER" || fail "Top-level launcher routing missing for: $pattern"
done

# 4. Verify the top-level dispatcher includes the exact script calls for the main command set.
for pattern in \
  'exec "$SCRIPTS/launcher.sh"' \
  'exec "$SCRIPTS/llama-ornith-serve.sh" install' \
  'exec "$SCRIPTS/giga-serve.sh" "$1"' \
  'exec "$SCRIPTS/internet-watchdog.sh" check' \
  'exec "$SCRIPTS/internet-watchdog.sh" reconnect' \
  'exec python3 "$ROOT/tests/run_all_tests.py"'; do
  rg -Fq -- "$pattern" "$LAUNCHER" || fail "Dispatcher is missing route for: $pattern"
done

printf 'PASS: launcher menu options 1..7 and command aliases are routed and documented.\n'
