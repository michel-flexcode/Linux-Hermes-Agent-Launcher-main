#!/usr/bin/env bash
# ============================================================================
# test_build_toolchain.sh
#
# Verifies the host can actually satisfy scripts/ensure-llama-server.sh: if no
# llama-server binary is already installed, git + make (or cmake) + a C/C++
# compiler must be available, otherwise the automatic source build will fail.
# ============================================================================
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
info() { printf 'INFO: %s\n' "$*"; }

has_llama_server() {
  command -v llama-server >/dev/null 2>&1 \
    || [[ -x /usr/bin/llama-server ]] \
    || [[ -x /usr/local/bin/llama-server ]] \
    || [[ -x "$HOME/.local/bin/llama-server" ]] \
    || [[ -x "$ROOT/bin/llama-server" ]]
}

if has_llama_server; then
  info 'llama-server is already installed; the source build toolchain is not required.'
  printf 'PASS: llama-server already present, build toolchain check skipped.\n'
  exit 0
fi

command -v git >/dev/null 2>&1 || fail 'git is required to clone llama.cpp (see scripts/ensure-llama-server.sh).'

command -v make >/dev/null 2>&1 || command -v cmake >/dev/null 2>&1 \
  || fail 'Neither make nor cmake is available; llama.cpp cannot be built from source.'

command -v gcc >/dev/null 2>&1 || command -v g++ >/dev/null 2>&1 || command -v cc >/dev/null 2>&1 \
  || fail 'No C/C++ compiler (gcc/g++/cc) found; llama.cpp cannot be built from source.'

printf 'PASS: git, a build system and a C/C++ compiler are available to build llama.cpp.\n'
