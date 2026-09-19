#!/usr/bin/env bash
# ============================================================================
# llama-ornith-serve.sh
# Déplie le service systemd exposant Ornith 35B-A3B via l'API OpenAI-compatible
# de llama.cpp (llama-server). Gestion START / STOP / STATUS / RESTART.
#
# CIBLE : RTX 3060 12 GB + Ryzen 7 5700G + 16 GB RAM (single channel).
#
# IMPORTANT (réalité llama.cpp) : le offload CUDA est ATOMIQUE PAR COUCHE.
# `-ngl N` déplace TOUTE la couche N (attention + MLP MoE + shared_expert) sur
# le GPU. ON NE PEUT PAS « garder Dense GPU / Experts CPU » avec le llama.cpp
# stock — cela exigerait HuggingFace/vLLM Megatron (incompatibles avec 12 GB).
#
# Strategie 12 GB :
#  - cache KV en GPU par defaut (quantise q4_0 pour reduire) ; ne jamais le
#    descendre sur le CPU (le bus DDR4 single channel détruirait tok/s).
#  - ctx 73728 (< 128K natif) ; 72K avec marge au-dessus du 65538 demandé.
#  - `NGLayers` : nombre de COUCHES à offloader. Ajuster pour tenir dans 12 GB.
#    L'Ornith alterne ~4 couches d'attention dense (MoE experts actifs) et ~28
#    couches d'attention lineaire (shared_expert seul, faible cout). Preferer
#    offloader en PRIORITE les couches dense => `-gl` plus bas, experts restant
#    sur CPU pour le reste. Tuner empiriquement (`status` -> VRAM).
# ============================================================================
set -uo pipefail
BASE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONF="$BASE/config/.env"

log(){ echo "[$(date +%H:%M:%S)] $*"; }
ok(){ echo "[$(date +%H:%M:%S)] ✔  $*"; }
fail(){ echo "[$(date +%H:%M:%S)] ERROR: $*" >&2; exit 1; }

has_sudo() { command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; }
IS_ROOT=false
[[ "$(id -u)" -eq 0 ]] && IS_ROOT=true

[[ -f "$CONF" ]] && . "$CONF"
# valeurs par défaut (dérivent de l'env si présent)
LISTEN_HOST="${LISTEN_HOST:-0.0.0.0}"
LISTEN_PORT="${LISTEN_PORT:-8080}"
CTX_SIZE="${CTX_SIZE:-73728}"
MODEL_BASENAME="${MODEL_FILENAME:-Ornith-1.5-35B-A3B-Q4_K_M.gguf}"
MODEL_DIR="${MODEL_DIR:-/opt/models}"
LLM_USER="${LLM_USER:-llmuser}"
NG_LAYERS="${NG_LAYERS:-1}"
THREADS="${THREADS:-0}"   # 0 = auto (core)
LOGDIR="${LOGDIR:-/opt/hermes-llm/logs}"

# sans root/sudo, /opt n'est pas inscriptible : bascule automatique vers $HOME
if [[ "$IS_ROOT" != true ]] && ! mkdir -p "$MODEL_DIR" "$LOGDIR" 2>/dev/null; then
  log "Pas d'accès root sur $MODEL_DIR / $LOGDIR ; bascule automatique vers \$HOME/.local."
  MODEL_DIR="$HOME/.local/models"
  LOGDIR="$HOME/.local/log/hermes-ornith"
  mkdir -p "$MODEL_DIR" "$LOGDIR"
fi
mkdir -p "$LOGDIR"
LOG="$LOGDIR/llama-ornith.out"
PIDFILE="$LOGDIR/llama-ornith.pid"

# localisation binaire (auto-détection, y compris l'install locale sans sudo)
LLAMA_BIN=""
for c in llama-server /usr/bin/llama-server /usr/local/bin/llama-server "$HOME/.local/bin/llama-server" "$BASE/bin/llama-server"; do
  if command -v "$c" >/dev/null 2>&1 || [[ -x "$c" ]]; then LLAMA_BIN="$c"; break; fi
done
if [[ -z "$LLAMA_BIN" ]]; then
  log "llama-server absent; tentative d'installation automatique..."
  "$BASE/scripts/ensure-llama-server.sh" >/dev/null 2>&1 || true
  for c in llama-server /usr/bin/llama-server /usr/local/bin/llama-server "$HOME/.local/bin/llama-server" "$BASE/bin/llama-server"; do
    if command -v "$c" >/dev/null 2>&1 || [[ -x "$c" ]]; then LLAMA_BIN="$c"; break; fi
  done
fi

UNIT="/etc/systemd/system/llama-ornith.service"

ensure_bin(){ [[ -n "$LLAMA_BIN" ]] || fail "llama-server introuvable. Installe-le avant."; }
ensure_unit(){ [[ -f "$UNIT" ]] || fail "Unité systemd absente. Lance d'abord ./llama-ornith-serve.sh install"; }

running_pid(){ [[ -f "$PIDFILE" ]] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; }

start_local(){
  ensure_bin
  if running_pid; then ok "Déjà en cours (pid $(cat "$PIDFILE"))."; return; fi
  # shellcheck disable=SC2046
  nohup "$LLAMA_BIN" $(build_cmd) >>"$LOG" 2>&1 &
  echo $! > "$PIDFILE"
  sleep 1
  if running_pid; then
    ok "Démarré en local (sans systemd, pid $(cat "$PIDFILE")). Log: $LOG"
  else
    fail "Échec du démarrage. Voir $LOG"
  fi
}

stop_local(){
  if running_pid; then
    kill "$(cat "$PIDFILE")" 2>/dev/null || true
    rm -f "$PIDFILE"
    ok "Arrêté."
  else
    log "Pas en cours d'exécution."
  fi
}

status_local(){
  if running_pid; then
    ok "En cours d'exécution (pid $(cat "$PIDFILE"))."
  else
    log "Arrêté."
  fi
  log "Dernières lignes du log:"
  tail -n 15 "$LOG" 2>/dev/null || true
}

# construction de la ligne de commande du serveur (flags llama.cpp REELS)
build_cmd(){
  ensure_bin
  echo "--model $MODEL_DIR/$MODEL_BASENAME"
  echo "--host $LISTEN_HOST"
  echo "--port $LISTEN_PORT"
  echo "--ctx-size $CTX_SIZE"
  echo "--gpu-layers $NG_LAYERS"
  echo "--cache-type-k q4_0"
  echo "--context-shift"
  [[ "$THREADS" -eq 0 ]] && echo "--threads 0" || echo "--threads $THREADS"
  echo "--log-disable"
  [[ -n "${LLM_API_KEY:-}" ]] && echo "--api-key $LLM_API_KEY"
}

command="${1:-}"
case "$command" in
  install)
    ensure_bin
    if [[ "$IS_ROOT" != true ]]; then
      log "Pas de droits root/sudo : installation systemd impossible."
      log "Démarrage automatique en mode local (sans persistance au redémarrage)."
      start_local
      log "Pour une installation systemd persistante, relance plus tard avec: sudo ./scripts/llama-ornith-serve.sh install"
      exit 0
    fi
    log "Installation de l'unité systemd..."
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
      echo "ExecStart=$LLAMA_BIN $(build_cmd | tr '\n' ' ')"
      echo
      echo "Restart=always"
      echo "RestartSec=5"
      echo
      echo "[Install]"
      echo "WantedBy=multi-user.target"
    } | sudo tee "$UNIT" >/dev/null
    sudo install -d -o "$LLM_USER" -g "$LLM_USER" "$MODEL_DIR" "$LOGDIR"
    sudo systemctl daemon-reload
    ok "Unité installée -> $UNIT"
    sudo systemctl enable --now llama-ornith.service
    log "Recharge la liste des modèles llama.cpp:"
    log "  curl -s -o /dev/null -w '%{http_code}\\n' http://127.0.0.1:$LISTEN_PORT/v1/models"
    ;;
  start|status|stop|restart)
    if [[ -f "$UNIT" ]] && { [[ "$IS_ROOT" == true ]] || has_sudo; }; then
      ensure_unit
      if [[ "$IS_ROOT" == true ]]; then
        systemctl "$command" llama-ornith.service || fail "Échec du $command"
      else
        sudo systemctl "$command" llama-ornith.service || fail "Échec du $command"
      fi
      if [[ "$command" == start || "$command" == restart || "$command" == status ]]; then
        sleep 1
        log "État du service:"
        sudo systemctl status llama-ornith.service --no-pager -l 2>/dev/null | head -20
        log "Dernières lignes du log:"
        tail -n 15 "$LOG" 2>/dev/null || true
      fi
    else
      case "$command" in
        start)   start_local ;;
        stop)    stop_local ;;
        restart) stop_local; start_local ;;
        status)  status_local ;;
      esac
    fi
    ;;
  *)
    fail "Usage: ./llama-ornith-serve.sh {install|start|stop|restart}"
    ;;
esac
