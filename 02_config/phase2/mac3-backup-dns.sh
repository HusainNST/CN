#!/usr/bin/env bash
# ABOUTME: Mac 3 parameterized backup dnsmasq resolver script for CN Project Phase 2 (Extension A).
# ABOUTME: Mirrors primary teamX.test records with local-ttl=30 and log-queries.
#
# Usage: ./mac3-backup-dns.sh [--render-only <OUT_CONF>] <MAC3_IP> <TARGET_EDGE_IP> [TTL=30]
#   e.g. ./mac3-backup-dns.sh 10.7.18.190 10.7.22.227
#   e.g. ./mac3-backup-dns.sh --render-only /tmp/backup-dns.conf 10.7.18.190 10.7.22.227 30
set -euo pipefail

validate_ipv4() {
  local ip="$1"
  local rx='^([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})$'
  if [[ ! "$ip" =~ $rx ]]; then
    return 1
  fi
  for octet in "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" "${BASH_REMATCH[3]}" "${BASH_REMATCH[4]}"; do
    if (( octet < 0 || octet > 255 )); then
      return 1
    fi
    if [[ ${#octet} -gt 1 && "${octet:0:1}" == "0" ]]; then
      return 1
    fi
  done
  return 0
}

validate_ttl() {
  local ttl="$1"
  if [[ ! "$ttl" =~ ^[0-9]+$ ]]; then
    return 1
  fi
  if (( ttl < 1 || ttl > 2147483647 )); then
    return 1
  fi
  if [[ ${#ttl} -gt 1 && "${ttl:0:1}" == "0" ]]; then
    return 1
  fi
  return 0
}

RENDER_ONLY=0
OUT_CONF=""

if [ "${1:-}" = "--render-only" ]; then
  if [ $# -lt 2 ]; then
    echo "Error: --render-only requires an output config path." >&2
    echo "Usage: $0 [--render-only <OUT_CONF>] <MAC3_IP> <TARGET_EDGE_IP> [TTL=30]" >&2
    exit 1
  fi
  RENDER_ONLY=1
  OUT_CONF="$2"
  shift 2
fi

if [ $# -lt 2 ] || [ $# -gt 3 ]; then
  echo "Usage: $0 [--render-only <OUT_CONF>] <MAC3_IP> <TARGET_EDGE_IP> [TTL=30]" >&2
  exit 1
fi

MAC3_IP="$1"
TARGET_EDGE_IP="$2"
TTL="${3:-30}"

if ! validate_ipv4 "$MAC3_IP"; then
  echo "Error: Invalid MAC3_IP IPv4 address: '$MAC3_IP'" >&2
  exit 1
fi

if ! validate_ipv4 "$TARGET_EDGE_IP"; then
  echo "Error: Invalid TARGET_EDGE_IP IPv4 address: '$TARGET_EDGE_IP'" >&2
  exit 1
fi

if ! validate_ttl "$TTL"; then
  echo "Error: Invalid TTL: '$TTL' (must be a positive integer)" >&2
  exit 1
fi

# Detect Homebrew prefix for dnsmasq log facility and config paths
if command -v brew >/dev/null 2>&1; then
  BREW_PREFIX="$(brew --prefix)"
elif [ -d "/opt/homebrew" ]; then
  BREW_PREFIX="/opt/homebrew"
elif [ -d "/usr/local" ]; then
  BREW_PREFIX="/usr/local"
else
  BREW_PREFIX="/opt/homebrew"
fi

render_dnsmasq_conf() {
  cat <<EOF
# ---- CN Project teamX : Mac 3 backup DNS (Extension A) ----
# Answer only on loopback and our LAN address
listen-address=127.0.0.1,$MAC3_IP
bind-interfaces

# Don't read /etc/resolv.conf; forward everything that isn't ours to public DNS
no-resolv
server=1.1.1.1
server=8.8.8.8
domain-needed
bogus-priv

# Authoritative for teamX.test: unknown names get NXDOMAIN, never forwarded
local=/teamX.test/

# Project A records -> edge
host-record=app.teamX.test,$TARGET_EDGE_IP
host-record=api.teamX.test,$TARGET_EDGE_IP

# TTL for our records, visible in dig's ANSWER section
local-ttl=$TTL

# Log every query - this is failover evidence
log-queries
log-facility=$BREW_PREFIX/var/log/dnsmasq.log
EOF
}

if [ "$RENDER_ONLY" -eq 1 ]; then
  mkdir -p "$(dirname "$OUT_CONF")"
  render_dnsmasq_conf > "$OUT_CONF"
  echo "Rendered backup dnsmasq configuration to $OUT_CONF"
  exit 0
fi

# Live mode: write to Homebrew dnsmasq directory and snapshot export
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SNAPSHOT_DIR="$REPO_ROOT/02_config/phase2/snapshots"
SNAPSHOT_FILE="$SNAPSHOT_DIR/dnsmasq-backup-mac3.conf"
LIVE_CONF_DIR="$BREW_PREFIX/etc/dnsmasq.d"
LIVE_CONF="$LIVE_CONF_DIR/teamX-backup.conf"

mkdir -p "$SNAPSHOT_DIR"
render_dnsmasq_conf > "$SNAPSHOT_FILE"
echo "Exported snapshot to $SNAPSHOT_FILE"

mkdir -p "$LIVE_CONF_DIR"
render_dnsmasq_conf > "$LIVE_CONF"
echo "Installed live configuration to $LIVE_CONF"

echo ""
echo "==== Next Steps on Mac 3 ===="
echo "1. Start or restart dnsmasq:"
echo "   sudo brew services restart dnsmasq"
echo "2. Verify dnsmasq listener on port 53:"
echo "   lsof -nP -i:53"
echo "3. Verify local resolution:"
echo "   dig @$MAC3_IP app.teamX.test +noall +answer"
