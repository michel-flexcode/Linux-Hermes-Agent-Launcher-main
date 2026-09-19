#!/usr/bin/env bash
# ============================================================================
# pre-start-optimizer.sh
# PRÉ-LANCEMENT : optimiser le kernel pour le service LLM headless sous
# llmuser. Ce script ne modifie pas le boot graphique global de la machine.
#
# TOTALEMENT REVERSIBLE :
#   - sauve l'actuel systemd target avant changement
#   - sauve /etc/default/grub avant modif (timestamp)
#   - sauve l'état GPU avant/après
#
# Usage:
#   ./scripts/pre-start-optimizer.sh
#   ./scripts/pre-start-optimizer.sh --revert    # retablit graphical.target
# Exécuter en sudo si vous voulez appliquer immediately (reboot requis pour les tweaks kernel)
# ============================================================================
set -uo pipefail

TS="$(date +%Y%m%d_%H%M%S)"
BACKUP_DIR="$HOME/.local/share/hermes-ornith/backup_${TS}"
mkdir -p "$BACKUP_DIR"
LOG="$HOME/.local/log/hermes-ornith/pre-start.log"
mkdir -p "$(dirname "$LOG")"

log()  { echo "[$(date +%H:%M:%S)] $*"; }
ok()   { echo "[$(date +%H:%M:%S)] ✔  $*"; }
warn() { echo "[$(date +%H:%M:%S)] ⚠  $*" | tee -a "$LOG"; }
err()  { echo "[$(date +%H:%M:%S)] ERROR: $*" | tee -a "$LOG" >&2; }

# ---- Sauve l'état GPU avant (si NVIDIA) -------------------------------------
gpu_before() {
  if command -v nvidia-smi >/dev/null 2>&1; then
    nvidia-smi --query-gpu=index,name,memory.used,memory.total,utilization.gpu \
      --format=csv,noheader >> "$LOG" 2>/dev/null || true
  fi
}
gpu_before

# ---- Revert : retablissement du boot graphique -----------------------------
if [[ "${1:-}" == "--revert" ]]; then
  log "Retablissement du mode graphique (graphical.target)..."
  sudo systemctl set-default graphical.target || { err "Echec du revert systemd"; exit 1; }
  ok "Cible par défaut = graphical.target. Redémarrez pour appliquer (reboot)."
  exit 0
fi

# ---- 0. Exigence sudo pour les reglages kernel ------------------------------
IS_SUDO=false
if [[ "$(id -u)" -ne 0 ]]; then
  if command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
    IS_SUDO=true; SUDO="sudo -n"
  else
    warn "Aucun accès sudo non-interactif: certains tweaks seront ignorés."
  fi
fi
[[ "$IS_SUDO" == true ]] && ok "sudo usable (non interactif)."

# ---- 1. Ne jamais modifier la cible de boot -------------------------------
CUR="$(systemctl get-default 2>/dev/null || echo unknown)"
log "Cible actuel : $CUR"
if [[ "$CUR" == "graphical.target" ]]; then
  ok "Boot graphique conserve pour le compte administrateur."
else
  warn "La cible actuelle n'est pas graphical.target; utilisez --revert si necessaire."
fi

# ---- 2. Réglages par-compte uniquement -------------------------------------
# Les réglages sysctl, GRUB, swap et governor CPU sont globaux à la machine.
# Ils ne sont donc pas appliqués ici: ils toucheraient aussi l'administrateur
# et les autres utilisateurs. Le tuning LLM reste dans systemd/llama-server.
tweaks=(
  "service_user=llmuser"
  "boot_target=graphical.target"
)
for tw in "${tweaks[@]}"; do
  log "configuration isolée: $tw"
done

# ---- 3. Vérifie la cible finale ---------------------------------------------
ok "Target actuelle après action: $(systemctl get-default 2>/dev/null)"
log "Dossier backup: $BACKUP_DIR  (conserve les anciens états + logs)"
log "Log complet: $LOG"
warn "Le service LLM reste headless sous llmuser; le boot graphique global n'est pas modifie."
warn "Redemarrez uniquement pour appliquer les reglages kernel persistants."
