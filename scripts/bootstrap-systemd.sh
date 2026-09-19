#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONF="$ROOT/config/.env"
UNIT="/etc/systemd/system/llama-ornith.service"

log(){ echo "[$(date +%H:%M:%S)] $*"; }
fail(){ echo "[$(date +%H:%M:%S)] ERROR: $*" >&2; exit 1; }

if [[ ! -f "$CONF" ]]; then
  fail "Missing runtime config: $CONF. Run ./launch.sh bootstrap first."
fi

# shellcheck disable=SC1090
. "$CONF"

LLM_USER="${LLM_USER:-llmuser}"
MODEL_DIR="${MODEL_DIR:-/opt/models}"
LOGDIR="${LOGDIR:-/opt/hermes-llm/logs}"
LISTEN_HOST="${LISTEN_HOST:-0.0.0.0}"
LISTEN_PORT="${LISTEN_PORT:-8080}"
CTX_SIZE="${CTX_SIZE:-73728}"
MODEL_FILENAME="${MODEL_FILENAME:-Ornith-1.5-35B-A3B-Q4_K_M.gguf}"
LLM_API_KEY="${LLM_API_KEY:-}"
NG_LAYERS="${NG_LAYERS:-1}"
THREADS="${THREADS:-0}"

if [[ "$(id -u)" -ne 0 ]]; then
  fail "This step requires root privileges. Run: sudo ./scripts/bootstrap-systemd.sh"
fi

LLAMA_BIN=""
for candidate in llama-server /usr/bin/llama-server /usr/local/bin/llama-server "$ROOT/bin/llama-server"; do
  if command -v "$candidate" >/dev/null 2>&1 || [[ -x "$candidate" ]]; then
    LLAMA_BIN="$candidate"
    break
  fi
done

if [[ -z "$LLAMA_BIN" ]]; then
  fail "llama-server is not installed. Run ./launch.sh install or ./scripts/ensure-llama-server.sh first."
fi

mkdir -p "$MODEL_DIR" "$LOGDIR"
install -d -o "$LLM_USER" -g "$LLM_USER" "$MODEL_DIR" "$LOGDIR"

if [[ ! -f "$MODEL_DIR/$MODEL_FILENAME" ]]; then
  fail "Model file is missing: $MODEL_DIR/$MODEL_FILENAME. Download it before installing the service."
fi

# Build the systemd unit in a deterministic way.
CMD=("$LLAMA_BIN" --model "$MODEL_DIR/$MODEL_FILENAME" --host "$LISTEN_HOST" --port "$LISTEN_PORT" --ctx-size "$CTX_SIZE" --gpu-layers "$NG_LAYERS" --cache-type-k q4_0 --context-shift --threads "${THREADS:-0}" --log-disable)
if [[ -n "$LLM_API_KEY" ]]; then
  CMD+=(--api-key "$LLM_API_KEY")
fi

{
  echo "[Unit]"
  echo "Description=Ornith 35B-A3B llama.cpp (OpenAI-compatible) server"
  echo "After=network-online.target"
  echo "Wants=network-online.target"
  echo
  echo "[Service]"
  echo "Type=exec"
  echo "User=$LLM_USER"
  echo "Group=$LLM_USER"
  echo "SupplementaryGroups=video render"
  echo "WorkingDirectory=$MODEL_DIR"
  echo "Environment=HOME=/home/$LLM_USER"
  echo "NoNewPrivileges=true"
  echo "PrivateTmp=true"
  echo
  printf 'ExecStart='; printf '%q ' "${CMD[@]}"; printf '\n'
  echo
  echo "Restart=always"
  echo "RestartSec=5"
  echo
  echo "[Install]"
  echo "WantedBy=multi-user.target"
} > "$UNIT"

systemctl daemon-reload
systemctl enable --now llama-ornith.service

if ! systemctl is-active --quiet llama-ornith.service; then
  log "Service failed to start. Showing current status:"
  systemctl status llama-ornith.service --no-pager -l || true
  tail -n 50 "$LOGDIR/llama-ornith.out" 2>/dev/null || true
  fail "llama-ornith.service is not active after installation."
fi

log "Systemd backend is installed and active: llama-ornith.service"
log "API Check: curl -sS http://127.0.0.1:$LISTEN_PORT/v1/models"
