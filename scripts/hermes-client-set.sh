#!/usr/bin/env bash
# ============================================================================
# hermes-client-set.sh — configurer le poste CLIENT (Hermes Agent)
#
# Pointe Hermes Agent vers le backend OpenAI-local à distance sans changer
# l'interface, la mémoire ni l'historique de session.
#
# LE SCRIPT NE S'EXÉCUTE PAS SUR LE SERVEUR — il est LÀ pour indiquer/commenter
# la config à appliquer sur le poste client Hermes.
#
# Usage (à adapter sur l'IP du serveur):
#   ./scripts/hermes-client-set.sh <IP_SERVEUR> <PORT> [http|https]
# Ex : ./scripts/hermes-client-set.sh 192.168.1.10 8080
# ============================================================================
set -uo pipefail
BASE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONF="$BASE/config/.env"

# IP/PORT par defaut (surchargés par l'env ou les args)
SERVER_IP="${1:-}"
PORT="${2:-}"
SCHEME="${3:-http}"
# charge les defs si présentes
if [[ -f "$CONF" ]]; then . "$CONF"; fi
SERVER_IP="${SERVER_IP:-$CLIENT_IP:-127.0.0.1}"
PORT="${PORT:-$LISTEN_PORT:-8080}"
SCHEME="${SCHEME:-http}"

info () { echo "[info]  $*"; }
warn () { echo "[! ]  $*" >&2; }

intro() {
  echo "========================================================"
  echo "  HERMES CLIENT SET — pointer Hermes vers le backend local"
  echo "========================================================"
  echo " Serveur : $SERVER_IP"
  echo " Port    : $PORT"
  echo " URL     : $SCHEME://$SERVER_IP:$PORT/v1"
  echo
}

show_openai() {
  echo "  --- OPTION A : API OpenAI-compatible (llama.cpp), recommandé ---"
  cat <<EOF
# sur le POSTE CLIENT (Hermes 0.21.1):
hermes config set providers.openai_compatible.base_url ${SCHEME}://${SERVER_IP}:${PORT}/v1
hermes config set providers.openai_compatible.api_key  sk-XXXX-PLACEHOLDER   # n'importe quelle chaîne
hermes config set providers.openai_compatible.model   local-ornith

# puis:
hermes model connect local-ornith
hermes connect
EOF
}

verify() {
  echo
  echo "  --- VÉRIFICATION RÉSEAU (à exécuter depuis l'ordinateur client) ---"
  echo "  curl -s -o /dev/null -w 'HTTP %{http_code}\\n' ${SCHEME}://${SERVER_IP}:${PORT}/v1/models"
  echo "  curl   ${SCHEME}://${SERVER_IP}:${PORT}/v1/chat/completions \\
         -H 'Content-Type: application/json' \\
         -d '{\"model\":\"local-ornith\",\"messages\":[{\"role\":\"user\",\"content\":\"salut\"}]}'"
  echo
  warn "Note: si c'est le même poste, teste tout de suite (option 4 du launcher)."
}

intro
show_openai
verify
