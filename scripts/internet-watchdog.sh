#!/usr/bin/env bash
# Monitor Internet connectivity and ask NetworkManager to reconnect devices.
set -uo pipefail

BASE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONF="$BASE/config/.env"
[[ -f "$CONF" ]] && . "$CONF"

CHECK_URL="${INTERNET_CHECK_URL:-https://connectivitycheck.gstatic.com/generate_204}"
CHECK_INTERVAL="${INTERNET_CHECK_INTERVAL:-30}"
NETWORK_INTERFACE="${NETWORK_INTERFACE:-}"
UNIT="/etc/systemd/system/hermes-internet-watchdog.service"
LOG_FILE="${INTERNET_LOG_FILE:-/var/log/hermes-internet-watchdog.log}"

log() {
  local message="[$(date '+%Y-%m-%d %H:%M:%S')] $*"
  printf '%s\n' "$message"
  if mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null && touch "$LOG_FILE" 2>/dev/null; then
    printf '%s\n' "$message" >> "$LOG_FILE" 2>/dev/null || true
  fi
}

check_internet() {
  curl --fail --silent --show-error --connect-timeout 5 --max-time 10 \
    -o /dev/null "$CHECK_URL"
}

reconnect_network() {
  command -v nmcli >/dev/null 2>&1 || {
    log 'NetworkManager/nmcli is unavailable; cannot reconnect automatically.'
    return 1
  }

  nmcli networking on >/dev/null 2>&1 || true

  if [[ -n "$NETWORK_INTERFACE" ]]; then
    nmcli device connect "$NETWORK_INTERFACE" >/dev/null 2>&1 || true
    return 0
  fi

  while read -r device; do
    [[ -n "$device" ]] || continue
    nmcli device connect "$device" >/dev/null 2>&1 || true
  done < <(nmcli -t -f DEVICE,TYPE,STATE device status \
    | awk -F: '$2 == "wifi" || $2 == "ethernet" { if ($3 != "connected") print $1 }')
}

run_watchdog() {
  log "Internet watchdog started; checking $CHECK_URL every ${CHECK_INTERVAL}s."
  while true; do
    if check_internet; then
      log 'Internet connection is available.'
    else
      log 'Internet connection is unavailable; requesting NetworkManager reconnect.'
      reconnect_network
    fi
    sleep "$CHECK_INTERVAL"
  done
}

install_unit() {
  [[ "$(id -u)" -eq 0 ]] || { printf 'Run install with sudo.\n' >&2; exit 1; }
  install -d -m 0755 "$(dirname "$LOG_FILE")"
  cat > "$UNIT" <<EOF
[Unit]
Description=Hermes Internet Connectivity Watchdog
After=NetworkManager.service network-online.target
Wants=NetworkManager.service network-online.target

[Service]
Type=simple
ExecStart=$BASE/scripts/internet-watchdog.sh run
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable --now hermes-internet-watchdog.service
  log "Installed and started $UNIT"
}

case "${1:-status}" in
  check)
    check_internet && log 'Internet connection is available.' || {
      log 'Internet connection is unavailable.'
      exit 1
    }
    ;;
  reconnect)
    reconnect_network
    ;;
  run)
    run_watchdog
    ;;
  install)
    install_unit
    ;;
  status)
    systemctl status hermes-internet-watchdog.service --no-pager -l
    ;;
  *)
    printf 'Usage: %s {check|reconnect|run|install|status}\n' "$0" >&2
    exit 2
    ;;
esac
