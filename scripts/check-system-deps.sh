#!/usr/bin/env bash
# ============================================================================
# check-system-deps.sh
# Verifies (and installs when possible) the system packages required to build
# and run llama-server: git, make, a C/C++ compiler, curl, python3, pip3.
# Used by `./launch.sh quickstart` before setup/bootstrap/install/api.
# ============================================================================
set -uo pipefail

log() { printf '%s\n' "[$(date +%H:%M:%S)] $*"; }
warn() { printf '%s\n' "[$(date +%H:%M:%S)] !  $*" >&2; }
fail() { printf '%s\n' "[$(date +%H:%M:%S)] ERROR: $*" >&2; exit 1; }

has_sudo() { command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; }
is_root() { [[ "$(id -u)" -eq 0 ]]; }

# command -> Debian/Ubuntu package providing it
pkg_for() {
  case "$1" in
    git) echo git ;;
    make|gcc|g++) echo build-essential ;;
    curl) echo curl ;;
    python3) echo python3 ;;
    pip3) echo python3-pip ;;
  esac
}

REQUIRED_CMDS=(git make gcc curl python3 pip3)
missing=()
for c in "${REQUIRED_CMDS[@]}"; do
  command -v "$c" >/dev/null 2>&1 || missing+=("$c")
done

if [[ ${#missing[@]} -eq 0 ]]; then
  log "Dépendances système déjà présentes: ${REQUIRED_CMDS[*]}."
  exit 0
fi

log "Dépendances manquantes: ${missing[*]}"

if ! command -v apt-get >/dev/null 2>&1; then
  fail "apt-get introuvable (distribution non Debian/Ubuntu). Installe manuellement: ${missing[*]}"
fi

packages=()
for c in "${missing[@]}"; do
  packages+=("$(pkg_for "$c")")
done
mapfile -t packages < <(printf '%s\n' "${packages[@]}" | sort -u)

if is_root; then
  apt-get update && apt-get install -y "${packages[@]}"
elif has_sudo; then
  sudo apt-get update && sudo apt-get install -y "${packages[@]}"
else
  fail "Pas d'accès sudo pour installer automatiquement: sudo apt-get install -y ${packages[*]}"
fi

still_missing=()
for c in "${REQUIRED_CMDS[@]}"; do
  command -v "$c" >/dev/null 2>&1 || still_missing+=("$c")
done
[[ ${#still_missing[@]} -eq 0 ]] || fail "Toujours manquant après installation: ${still_missing[*]}"

log "OK: ${REQUIRED_CMDS[*]} disponibles."
