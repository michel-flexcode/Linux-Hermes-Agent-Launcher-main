#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS="$ROOT/scripts"

usage() {
  cat <<EOF
Linux Hermes Agent Launcher

Usage: ./launch.sh <command>

Commands:
  menu       Open the interactive launcher menu (default)
  quickstart Check/install system deps, then setup, bootstrap, download model, install and validate the API
  setup      Create local config and secrets files
  bootstrap  Generate a coherent .env, validate the GGUF file and default runtime settings
  systemd    Install and enable the llama.cpp systemd service for the configured backend
  install    Ensure llama-server exists, then install and start the llama.cpp systemd service
  model      Download the Ornith GGUF model from Hugging Face into the configured model directory
  start      Start the LLM service
  stop       Stop the LLM service
  restart    Restart the LLM service
  status     Show service, GPU and API status
  models     List available GGUF models
  api        Validate the local OpenAI-compatible API endpoint
  internet   Check Internet connectivity
  reconnect  Request NetworkManager reconnection
  watchdog   Install and start the Internet watchdog
  tests      Run the local test suite
  help       Show this help
EOF
}

case "${1:-menu}" in
  menu)
    exec "$SCRIPTS/launcher.sh"
    ;;
  quickstart)
    "$SCRIPTS/check-system-deps.sh"
    "$ROOT/launch.sh" setup
    "$ROOT/launch.sh" bootstrap
    "$ROOT/launch.sh" model
    "$ROOT/launch.sh" install
    exec "$ROOT/launch.sh" api
    ;;
  setup)
    exec "$SCRIPTS/launcher.sh" <<< '1'
    ;;
  bootstrap)
    exec "$SCRIPTS/bootstrap-config.sh"
    ;;
  systemd)
    exec sudo "$SCRIPTS/bootstrap-systemd.sh"
    ;;
  install)
    "$SCRIPTS/ensure-llama-server.sh"
    exec "$SCRIPTS/llama-ornith-serve.sh" install
    ;;
  model)
    exec "$SCRIPTS/download-ornith-model.sh"
    ;;
  start|stop|restart|status)
    exec "$SCRIPTS/giga-serve.sh" "$1"
    ;;
  models)
    exec "$SCRIPTS/giga-serve.sh" models
    ;;
  api)
    exec "$SCRIPTS/api-validate.sh"
    ;;
  internet)
    exec "$SCRIPTS/internet-watchdog.sh" check
    ;;
  reconnect)
    exec "$SCRIPTS/internet-watchdog.sh" reconnect
    ;;
  watchdog)
    exec "$SCRIPTS/internet-watchdog.sh" install
    ;;
  tests)
    exec python3 "$ROOT/tests/run_all_tests.py"
    ;;
  help|-h|--help)
    usage
    ;;
  *)
    printf 'Unknown command: %s\n\n' "$1" >&2
    usage >&2
    exit 2
    ;;
esac
