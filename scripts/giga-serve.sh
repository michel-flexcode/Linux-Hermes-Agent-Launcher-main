#!/usr/bin/env bash
# ============================================================================
# giga-serve.sh
# GESTION GLOBALE du serveur à distance (START / STOP / SWITCH MODEL / STATUS).
#
# Pilotage à distance via SSH — ni écran ni souris nécessaires.
#   ./giga-serve.sh status          -> état + GPU usage
#   ./giga-serve.sh models          -> liste les GGUF disponibles
#   ./giga-serve.sh switch <GGUF>   -> bascule de modèle (réarmand systemd)
#   ./giga-serve.sh start|stop|restart
# ============================================================================
set -uo pipefail
BASE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONF="$BASE/config/.env"
[[ -f "$CONF" ]] && . "$CONF"

MODEL_DIR="${MODEL_DIR:-$HOME/.local/models}"
MODEL_BASENAME="${MODEL_FILENAME:-Ornith-1.5-35B-A3B-Q4_K_M.gguf}"
LOGDIR="$HOME/.local/log/hermes-ornith"
mkdir -p "$LOGDIR" "$MODEL_DIR"

log(){ echo "[$(date +%H:%M:%S)] $*"; }
info(){ echo "[$(date +%H:%M:%S)] i  $*"; }
warn(){ echo "[$(date +%H:%M:%S)] !  $*" | tee -a "$LOGDIR/switch.log"; }
fail(){ echo "[$(date +%H:%M:%S)] X  $*" >&2; exit 1; }

SERVICE=llama-ornith
LISTEN_PORT="${LISTEN_PORT:-8080}"
SERVE_SCRIPT="$BASE/scripts/llama-ornith-serve.sh"

has_sudo() { command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; }
uses_systemd() {
  [[ -f "/etc/systemd/system/$SERVICE.service" ]] && { [[ "$(id -u)" -eq 0 ]] || has_sudo; }
}

# ---- status : état du service + GPU + probe API ----------------------------
status() {
  log "===== État du service '$SERVICE' ====="
  if uses_systemd; then
    systemctl is-active "$SERVICE" 2>/dev/null || true
    systemctl status "$SERVICE" --no-pager -l 2>/dev/null | head -15 || true
  else
    "$SERVE_SCRIPT" status || true
  fi

  echo
  log "===== Usage GPU (RTX 3060) ====="
  if command -v nvidia-smi >/dev/null 2>&1; then
    nvidia-smi --query-gpu=name,memory.used,memory.total,utilization.gpu \
      --format=csv,noheader 2>/dev/null || warn "nvidia-smi illisible."
  else
    warn "nvidia-smi absent (pilote CUDA ?)."
  fi

  echo
  log "===== Probe API OpenAI ($(HOSTNAME)) ====="
  local code
  code=$(curl -s -o /dev/null -w "%{http_code}" "http://127.0.0.1:$LISTEN_PORT/v1/models" 2>/dev/null || echo "000")
  if [[ "$code" == "200" ]]; then
    log "Répond au /v1/models (HTTP $code)."
  else
    warn "Aucune réponse (HTTP $code). Lance: ./giga-serve.sh start"
  fi
}

# ---- models : liste des GGUF -> /opt/models ------------------------------
models() {
  log "==== GGUF disponibles ($MODEL_DIR) ===="
  ls -lh "$MODEL_DIR"/*.gguf 2>/dev/null || warn "Aucun .gguf dans $MODEL_DIR"
  echo
  log "Modèle courant (config): $MODEL_BASENAME"
  log "GPU (unitaire): $(command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null || echo 'n/a')"
}

# ---- switch : bascule de modèle -------------------------------------------
switch() {
  local new="${1:?Usage: ./giga-serve.sh switch <GGUF>}"
  local target="$MODEL_DIR/$new"
  [[ -f "$target" ]] || fail "Modèle introuvable: $target (liste avec 'models')"
  local cur
  cur="$(basename "$(ls -m "$MODEL_DIR")" 2>/dev/null || basename "$MODEL_BASENAME")"

  warn "Bascul de $cur -> $new"

  # bascule l-environnement: remplace MODEL_FILENAME dans l'env
  if [[ -f "$CONF" ]]; then
    tmp="$(mktemp)"
    sed -E "s/^MODEL_FILENAME=.*/MODEL_FILENAME=$new/" "$CONF" > "$tmp"
    mv "$tmp" "$CONF"
    info "config/.env : MODEL_FILENAME=$new"
  fi

  # réarmand IMMÉDIATEMENT le serveur avec le nouveau modèle (systemd si dispo, sinon process local)
  if uses_systemd; then
    systemctl daemon-reload
    systemctl restart "$SERVICE" 2>/dev/null \
      && info "Service réarmand avec $new." \
      || warn "Réarm échoué. Redémarre manuellement: sudo systemctl restart $SERVICE"
  else
    "$SERVE_SCRIPT" restart \
      && info "Serveur local réarmand avec $new." \
      || warn "Réarm échoué. Vérifie: $SERVE_SCRIPT status"
  fi
  info "Le client Hermes verra le nouveau modèle au prochain appel (base_url inchangée)."
}

# ---- main -----------------------------------------------------------------
case "${1:-}" in
  status) status;      ;;
  models) models;      ;;
  switch) shift; switch "$@"; ;;
  start)   if uses_systemd; then systemctl start   "$SERVICE"; else "$SERVE_SCRIPT" start;   fi ;;
  stop)    if uses_systemd; then systemctl stop    "$SERVICE"; else "$SERVE_SCRIPT" stop;    fi ;;
  restart) if uses_systemd; then systemctl restart "$SERVICE"; else "$SERVE_SCRIPT" restart; fi ;;
  *) fail "Usage:\n  ./giga-serve.sh status|models|switch <GGUF>|start|stop|restart" ;;
esac
