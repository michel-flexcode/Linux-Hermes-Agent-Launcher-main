#!/usr/bin/env bash
# ============================================================================
# launcher.sh — menu interactif du Linux-Hermes-Agent-Launcher
#
# Utilise les autres scripts pour:
#   - générer les secrets (.env)
#   - lancer l'optimiseur sans modifier le boot graphique
#   - installer / gérer le serveur systemd
#   - switch de modèle + diagnostic
# ============================================================================
set -uo pipefail
BASE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPTS="$BASE/scripts"
CONF="$BASE/config/.env"
SECRET="$BASE/config/secrets.env"

line() { printf '%.0s-' {1..1} >/dev/null; echo "========================================================"; }
intro() {
  line
  echo "   LINUX HERMES AGENT LAUNCHER — Ornith 35B-A3B (headless OpenAI backend)"
  line
  echo "   Box cible: RTX 3060 12GB · 16GB DDR4 single-channel · Ryzen 7 5700G"
  echo "   HARD contexte Hermes: >=65538 tokens (on cible 73728 / 72K)"
  line
}

has_sudo() { command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; }

gen_env() {
  echo "=== 1/3 — Générer l'environnement (.env)"
  if [[ ! -f "$CONF" ]]; then
    cp "$BASE/config/.env.example" "$CONF"
    echo "   Copié .env.example -> $CONF"
  else
    echo "   .env existe déjà. Ne pas écraser."
  fi

  # secrets
  if [[ ! -f "$SECRET" ]]; then
    cp "$BASE/config/secrets.env.example" "$SECRET"
  fi
  # génère un secret aléatoire si vide (format sk-XXXX)
  local existing
  existing=$(grep -E '^LLM_API_KEY=' "$SECRET" | cut -d= -f2)
  if [[ -z "$existing" || "$existing" == "CHANGE_ME_generate_a_random_key" ]]; then
    newsk="$(head -c 24 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | cut -c1-32)"
    sed -i -E "s/^LLM_API_KEY=.*/LLM_API_KEY=sk-$newsk/" "$SECRET"
    echo "   Génération d'une clé API: sk-........ (taille 32 carères)"
  else
    echo "   Clé API présente. Ne pas écraser."
  fi
  chmod 600 "$SECRET" 2>/dev/null || true
  echo
  echo "   Copie pour l'USAGE sur le SERVER (env):"
  echo "     cp $CONF /opt/hermes-ornith/env   (sur le serveur cible)"
  echo
  echo "   REMPLIS: $CONF"
  echo "     LISTEN_HOST=0.0.0.0   PORT=$((RANDOM+8000))   CTX_SIZE=73728"
  echo "     MODEL_FILENAME=...Q4_K_M.gguf   CLIENT_IP=<IP client Hermes>"
}

optimize() {
  echo "=== 2/3 — Optimiseur kernel (service headless sous llmuser)"
  if has_sudo; then
    sudo "$BASE/scripts/pre-start-optimizer.sh"
  else
    echo "   (sudo requis pour les reglages kernel)"
    "$BASE/scripts/pre-start-optimizer.sh"
  fi
  echo
  echo "   Le boot graphique global n'est pas modifie. Redemarrez seulement pour appliquer les tweaks kernel."
}

serve() {
  echo "=== 3/3 — Démarrage / gestion du serveur systemd"
  echo
  echo "Lance le benchmark / statut GPU d'abord:"
  "$BASE/scripts/giga-serve.sh" status 2>/dev/null || echo "(aucun service actif)"
  echo
  read -rp "Installer / démarrer le service ? [y/N] " ans
  if [[ "$ans" =~ ^[Yy] ]]; then
    if has_sudo; then
      sudo "$BASE/scripts/llama-ornith-serve.sh" install
    else
      "$BASE/scripts/llama-ornith-serve.sh" install
    fi
    echo
    "$BASE/scripts/giga-serve.sh" status
  fi
}

main() {
  intro
  echo "Options:"
  echo "  1) Configurer .env + secrets"
  echo "  2) Optimiser le systeme sans couper le bureau"
  echo "  3) Gérer le service"
  echo "  4) Status GPU / API (diagnostic)"
  echo "  5) Lister les modèles GGUF"
  echo "  6) Basculer de modèle (switch)"
  echo "  7) Vérifier la connexion Internet"
  echo "  x) Quitter"
  echo
  read -rp "Choix [1-x]: " c
  case "$c" in
    1) gen_env;;
    2) optimize;;
    3) serve;;
    4) "$BASE/scripts/giga-serve.sh" status;;
    5) "$BASE/scripts/giga-serve.sh" models;;
    6)
        "$BASE/scripts/giga-serve.sh" models
        read -rp "Modèle (nom GGUF exact, sans .gguf): " m
        [[ -n "$m" ]] && "$BASE/scripts/giga-serve.sh" switch "${m%.gguf}"
        ;;
    7) "$BASE/scripts/internet-watchdog.sh" check;;
    x|X|""|q) echo "Bye";;
    *) echo "Choix inconnu.";;
  esac
}

main
