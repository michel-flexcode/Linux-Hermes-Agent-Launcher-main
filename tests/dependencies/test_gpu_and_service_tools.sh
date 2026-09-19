#!/usr/bin/env bash
# ============================================================================
# test_gpu_and_service_tools.sh
#
# Reports the availability of the optional runtime tools used by
# scripts/giga-serve.sh (nvidia-smi) and the systemd-backed install path
# (systemctl). Neither is a hard requirement anymore: giga-serve.sh already
# warns and continues without nvidia-smi, and llama-ornith-serve.sh falls
# back to a local PID-managed process when systemd/root is unavailable. This
# test is informational and only fails if the check itself cannot run.
# ============================================================================
set -uo pipefail

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
warn() { printf 'WARN: %s\n' "$*"; }
info() { printf 'INFO: %s\n' "$*"; }

if command -v nvidia-smi >/dev/null 2>&1; then
  info "nvidia-smi found: $(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -n1)"
else
  warn 'nvidia-smi not found; GPU offload status/VRAM checks will be unavailable (CPU-only fallback).'
fi

if command -v systemctl >/dev/null 2>&1; then
  info 'systemctl found; persistent systemd install is possible with root/sudo.'
else
  warn 'systemctl not found; the service will always run in local (non-systemd) mode.'
fi

printf 'PASS: optional GPU/systemd tooling checked (see INFO/WARN above); no hard requirement enforced.\n'
