#!/usr/bin/env bash
# Shared network inventory and helpers for live demo scripts.
# Update the four IPs below if campus DHCP assigns new leases on demo day.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

MAC1_IP="${MAC1_IP:-10.7.4.108}"     # Navodit: Primary DNS + client
MAC2_IP="${MAC2_IP:-10.7.6.184}"     # Sarvesh: Primary HTTPS edge / LB / CA
MAC3_IP="${MAC3_IP:-10.7.30.194}"    # Trishit: Backend A (:3001) + Backup DNS
MAC4_IP="${MAC4_IP:-10.7.3.254}"     # Husain:  Backend B (:3002) + Standby edge + client

DOMAIN="${DOMAIN:-app.teamX.test}"
API_DOMAIN="${API_DOMAIN:-api.teamX.test}"
TTL="${TTL:-30}"
CA_CERT="$REPO_ROOT/02_config/teamX-rootCA.crt"

# Prefer /usr/bin/curl and /usr/bin/openssl to avoid macOS Local Network
# permission issues seen with Homebrew binaries on LAN addresses.
CURL_BIN="${CURL_BIN:-/usr/bin/curl}"
OPENSSL_BIN="${OPENSSL_BIN:-/usr/bin/openssl}"

if command -v brew >/dev/null 2>&1; then
  BREW_PREFIX="$(brew --prefix)"
elif [ -d /opt/homebrew ]; then
  BREW_PREFIX="/opt/homebrew"
else
  BREW_PREFIX="/usr/local"
fi

banner() {
  printf '\n=== %s ===\n' "$1"
}

show_lan_info() {
  local self_label="$1"
  shift
  banner "$self_label — Network Info"
  date
  echo "IPv4 (en0): $(ipconfig getifaddr en0 || echo 'unavailable')"
  route -n get default 2>/dev/null | grep -E "gateway|interface" || true
  ipconfig getpacket en0 2>/dev/null | grep -E "chaddr|yiaddr|subnet_mask" || true
  banner "$self_label — Ping Peers"
  for peer in "$@"; do
    echo "--- ping $peer ---"
    ping -c 3 "$peer"
  done
}

flush_dns_cache() {
  sudo dscacheutil -flushcache
  sudo killall -HUP mDNSResponder
  echo "Flushed macOS DNS cache."
}

check_lb_six() {
  banner "Load Balancing Check (6 requests to https://$DOMAIN/api/status)"
  for i in 1 2 3 4 5 6; do
    printf 'Request %d: ' "$i"
    "$CURL_BIN" --cacert "$CA_CERT" -sS -D - -o /dev/null "https://$DOMAIN/api/status" \
      | grep -iE "^HTTP|^x-backend|^x-edge|^x-upstream" \
      | tr '\r\n' ' '
    echo ""
  done
}
