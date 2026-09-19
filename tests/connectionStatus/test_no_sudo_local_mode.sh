#!/usr/bin/env bash
# ============================================================================
# test_no_sudo_local_mode.sh
#
# Behavioral regression test for the no-sudo / no-systemd fallback added to
# scripts/ensure-llama-server.sh, scripts/llama-ornith-serve.sh and
# scripts/giga-serve.sh. Runs the real scripts (copied into an isolated
# sandbox) against a fake llama-server binary, entirely as an unprivileged
# user, with no systemd unit installed. Does not touch the real config/.env,
# does not require sudo, and does not start the real model.
# ============================================================================
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

for f in ensure-llama-server.sh llama-ornith-serve.sh giga-serve.sh; do
  [[ -f "$ROOT/scripts/$f" ]] || fail "$f is missing."
done

SANDBOX="$(mktemp -d)"
TMP_HOME="$SANDBOX/home"
FAKE_BIN="$SANDBOX/fakebin"
PROJECT="$SANDBOX/project"
mkdir -p "$TMP_HOME" "$FAKE_BIN" "$PROJECT/scripts" "$PROJECT/config"

cleanup() {
  [[ -f "$PIDFILE_PATH" ]] && kill "$(cat "$PIDFILE_PATH" 2>/dev/null)" 2>/dev/null
  pkill -f "$FAKE_BIN/llama-server" 2>/dev/null
  rm -rf "$SANDBOX"
}
trap cleanup EXIT

# Isolated copy of the project so BASE/config/.env resolution stays self-contained.
cp "$ROOT/scripts/ensure-llama-server.sh" "$ROOT/scripts/llama-ornith-serve.sh" "$ROOT/scripts/giga-serve.sh" "$PROJECT/scripts/"
cat > "$PROJECT/config/.env" <<EOF
LLM_USER=llmuser
MODEL_DIR=/root/forbidden-models
LOGDIR=/root/forbidden-logs
LISTEN_HOST=0.0.0.0
LISTEN_PORT=18080
CTX_SIZE=73728
MODEL_FILENAME=test-model.gguf
EOF

SERVE_SCRIPT="$PROJECT/scripts/llama-ornith-serve.sh"
GIGA_SCRIPT="$PROJECT/scripts/giga-serve.sh"
ENSURE_SCRIPT="$PROJECT/scripts/ensure-llama-server.sh"
PIDFILE_PATH="$TMP_HOME/.local/log/hermes-ornith/llama-ornith.pid"

# Minimal stand-in for llama-server: stays alive until it receives SIGTERM.
cat > "$FAKE_BIN/llama-server" <<'EOF'
#!/usr/bin/env bash
trap 'exit 0' TERM INT
while :; do sleep 1; done
EOF
chmod +x "$FAKE_BIN/llama-server"

run_serve() { HOME="$TMP_HOME" PATH="$FAKE_BIN:$PATH" "$SERVE_SCRIPT" "$@"; }
run_giga()  { HOME="$TMP_HOME" PATH="$FAKE_BIN:$PATH" "$GIGA_SCRIPT" "$@"; }

# ---------------------------------------------------------------------------
# A. ensure-llama-server.sh must detect a locally installed binary
#    (~/.local/bin/llama-server) without sudo, network or a git clone.
# ---------------------------------------------------------------------------
LOCAL_BIN_DIR="$TMP_HOME/.local/bin"
mkdir -p "$LOCAL_BIN_DIR"
cp "$FAKE_BIN/llama-server" "$LOCAL_BIN_DIR/llama-server"

out="$(HOME="$TMP_HOME" PATH=/usr/bin:/bin "$ENSURE_SCRIPT" 2>&1)" || fail "ensure-llama-server.sh failed on an existing local binary:\n$out"
printf '%s\n' "$out" | grep -q "$LOCAL_BIN_DIR/llama-server" \
  || fail "ensure-llama-server.sh did not detect the ~/.local/bin binary: $out"
printf '%s\n' "$out" | grep -qi 'cloning llama.cpp' \
  && fail "ensure-llama-server.sh tried to rebuild llama.cpp although a local binary already existed."

rm -f "$LOCAL_BIN_DIR/llama-server"

# ---------------------------------------------------------------------------
# B. llama-ornith-serve.sh start/status/stop must work with no root, no sudo
#    and no systemd unit, automatically falling back to $HOME/.local and to
#    PID-file based process management.
# ---------------------------------------------------------------------------
out="$(run_serve start 2>&1)" || fail "start (local mode) failed:\n$out"
printf '%s\n' "$out" | grep -qi 'local' \
  || fail "start did not report local (no-systemd) mode: $out"

[[ -f "$PIDFILE_PATH" ]] || fail 'PID file was not created under $HOME/.local (no-root fallback path).'
kill -0 "$(cat "$PIDFILE_PATH")" 2>/dev/null || fail 'Local server process is not running after start.'

out="$(run_serve status 2>&1)" || fail "status failed:\n$out"
printf '%s\n' "$out" | grep -q "En cours d'exécution" \
  || fail "status did not detect the running local process: $out"

# ---------------------------------------------------------------------------
# C. giga-serve.sh must delegate to the same local process manager instead of
#    calling systemctl when no systemd unit is installed.
# ---------------------------------------------------------------------------
out="$(run_giga status 2>&1)" || fail "giga-serve.sh status failed:\n$out"
printf '%s\n' "$out" | grep -q "En cours d'exécution" \
  || fail "giga-serve.sh did not report the local server as running: $out"

out="$(run_giga stop 2>&1)" || fail "giga-serve.sh stop failed:\n$out"
sleep 1
kill -0 "$(cat "$PIDFILE_PATH" 2>/dev/null)" 2>/dev/null \
  && fail 'Process is still running after giga-serve.sh stop.'
[[ -f "$PIDFILE_PATH" ]] && fail 'PID file was not removed after stop.'

printf 'PASS: no-sudo/no-systemd fallback works end-to-end (install detection, start/status/stop lifecycle, giga-serve delegation).\n'
