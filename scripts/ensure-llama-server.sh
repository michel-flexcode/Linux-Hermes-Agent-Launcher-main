#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET_BIN="${TARGET_BIN:-/usr/local/bin/llama-server}"
LOCAL_BIN_DIR="$HOME/.local/bin"
LOCAL_TARGET_BIN="$LOCAL_BIN_DIR/llama-server"

log() { printf '%s\n' "[$(date +%H:%M:%S)] $*"; }
fail() { printf '%s\n' "[$(date +%H:%M:%S)] ERROR: $*" >&2; exit 1; }

has_sudo() { command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; }

has_llama_server() {
  command -v llama-server >/dev/null 2>&1 \
    || [[ -x /usr/bin/llama-server ]] \
    || [[ -x /usr/local/bin/llama-server ]] \
    || [[ -x "$ROOT/bin/llama-server" ]] \
    || [[ -x "$LOCAL_TARGET_BIN" ]]
}

build_llama_server() {
  # builds the binary into $1/build/bin/llama-server and echoes the build dir
  if ! command -v git >/dev/null 2>&1; then
    fail 'git is required to build llama.cpp from source.'
  fi
  if ! command -v make >/dev/null 2>&1; then
    fail 'make is required to build llama.cpp from source.'
  fi

  log 'llama-server not found; cloning llama.cpp source and building it.'
  tmpdir="$(mktemp -d)"
  trap 'rm -rf "$tmpdir"' EXIT

  git clone --depth 1 https://github.com/ggerganov/llama.cpp.git "$tmpdir/llama.cpp"
  cd "$tmpdir/llama.cpp"
  make -j"$(nproc)"
  printf '%s\n' "$tmpdir/llama.cpp"
}

install_from_source() {
  builddir="$(build_llama_server)"
  install -m 0755 "$builddir/build/bin/llama-server" "$TARGET_BIN"
  log "llama-server installed at $TARGET_BIN"
}

install_from_source_local() {
  # no root/sudo available: install into the user's own bin directory instead
  builddir="$(build_llama_server)"
  mkdir -p "$LOCAL_BIN_DIR"
  install -m 0755 "$builddir/build/bin/llama-server" "$LOCAL_TARGET_BIN"
  log "llama-server installed at $LOCAL_TARGET_BIN (no root available)"
  case ":$PATH:" in
    *":$LOCAL_BIN_DIR:"*) : ;;
    *) log "Add '$LOCAL_BIN_DIR' to PATH (e.g. in ~/.bashrc) to use 'llama-server' directly." ;;
  esac
}

if has_llama_server; then
  log "llama-server detected: $(command -v llama-server || ls "$LOCAL_TARGET_BIN" /usr/local/bin/llama-server /usr/bin/llama-server 2>/dev/null | head -n1)"
  exit 0
fi

if [[ "$(id -u)" -eq 0 ]]; then
  install_from_source
elif has_sudo; then
  log 'Not running as root; using sudo for the installation step.'
  sudo -- bash -c "$(declare -f build_llama_server has_llama_server install_from_source); TARGET_BIN='$TARGET_BIN'; install_from_source"
else
  log 'No sudo access available; installing llama-server locally for the current user.'
  install_from_source_local
fi

if ! has_llama_server; then
  fail 'llama-server installation failed; no binary was detected afterward.'
fi
