#!/usr/bin/env bash
# ABOUTME: Mac 1 primary dnsmasq Phase 2 script (P2-01): renders teamX.test records with a short TTL.
# ABOUTME: Rerun with a different edge IP to switch app/api.teamX.test for the TTL and cutover demos.
#
# Usage: ./mac1-dns-phase2.sh [--render-only <OUT_CONF>] <MAC1_IP> <TARGET_EDGE_IP> [TTL=30]
#   e.g. ./mac1-dns-phase2.sh 10.7.10.22 10.7.22.227          # normal: records point at Mac 2
#   e.g. ./mac1-dns-phase2.sh 10.7.10.22 10.7.24.166 30       # cutover: records point at Mac 4 standby
#   e.g. ./mac1-dns-phase2.sh --render-only /tmp/p.conf 10.7.10.22 10.7.22.227
set -euo pipefail

USAGE="Usage: $0 [--render-only <OUT_CONF>] <MAC1_IP> <TARGET_EDGE_IP> [TTL=30]"

validate_ipv4() {
  local rx='^([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})$'
  [[ "$1" =~ $rx ]] || return 1
  local octet
  for octet in "${BASH_REMATCH[@]:1}"; do
    (( octet <= 255 )) || return 1
    [[ ${#octet} -eq 1 || "${octet:0:1}" != "0" ]] || return 1
  done
}

validate_ttl() {
  [[ "$1" =~ ^[1-9][0-9]{0,8}$ ]]
}

RENDER_ONLY=0
OUT_CONF=""
if [ "${1:-}" = "--render-only" ]; then
  if [ $# -lt 2 ]; then
    echo "Error: --render-only requires an output config path." >&2
    echo "$USAGE" >&2
    exit 1
  fi
  RENDER_ONLY=1
  OUT_CONF="$2"
  shift 2
fi

if [ $# -lt 2 ] || [ $# -gt 3 ]; then
  echo "$USAGE" >&2
  exit 1
fi

MAC1_IP="$1"
TARGET_EDGE_IP="$2"
TTL="${3:-30}"

validate_ipv4 "$MAC1_IP" || { echo "Error: Invalid MAC1_IP IPv4 address: '$MAC1_IP'" >&2; exit 1; }
validate_ipv4 "$TARGET_EDGE_IP" || { echo "Error: Invalid TARGET_EDGE_IP IPv4 address: '$TARGET_EDGE_IP'" >&2; exit 1; }
validate_ttl "$TTL" || { echo "Error: Invalid TTL: '$TTL' (must be a positive integer)" >&2; exit 1; }

if command -v brew >/dev/null 2>&1; then
  BREW_PREFIX="$(brew --prefix)"
elif [ -d /opt/homebrew ]; then
  BREW_PREFIX="/opt/homebrew"
else
  BREW_PREFIX="/usr/local"
fi

render_dnsmasq_conf() {
  cat <<EOF
# ---- CN Project teamX : Mac 1 primary DNS (Phase 2, Extensions A, B, E) ----
# Answer only on loopback and our LAN address
listen-address=127.0.0.1,$MAC1_IP
bind-interfaces

# Don't read /etc/resolv.conf; forward everything that isn't ours to public DNS
no-resolv
server=1.1.1.1
server=8.8.8.8
domain-needed
bogus-priv

# Authoritative for teamX.test: unknown names get NXDOMAIN, never forwarded
local=/teamX.test/

# Project A records -> current edge (Mac 2 normally, Mac 4 standby during cutover)
host-record=app.teamX.test,$TARGET_EDGE_IP
host-record=api.teamX.test,$TARGET_EDGE_IP

# Short TTL so cached answers expire quickly during record changes
local-ttl=$TTL

# Log every query - this is evidence
log-queries
log-facility=$BREW_PREFIX/var/log/dnsmasq.log
EOF
}

if [ "$RENDER_ONLY" -eq 1 ]; then
  mkdir -p "$(dirname "$OUT_CONF")"
  render_dnsmasq_conf > "$OUT_CONF"
  echo "Rendered primary dnsmasq configuration to $OUT_CONF"
  exit 0
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SNAPSHOT_DIR="$REPO_ROOT/02_config/phase2/snapshots"
SNAPSHOT_FILE="$SNAPSHOT_DIR/dnsmasq-primary-mac1.conf"
LIVE_CONF_DIR="$BREW_PREFIX/etc/dnsmasq.d"
LIVE_CONF="$LIVE_CONF_DIR/teamX-phase2.conf"

mkdir -p "$SNAPSHOT_DIR" "$LIVE_CONF_DIR"
render_dnsmasq_conf > "$LIVE_CONF"
render_dnsmasq_conf > "$SNAPSHOT_FILE"
echo "Installed live configuration to $LIVE_CONF"
echo "Exported snapshot to $SNAPSHOT_FILE"

echo ""
echo "==== Next Steps on Mac 1 ===="
echo "0. Make sure $BREW_PREFIX/etc/dnsmasq.conf has 'conf-dir=$LIVE_CONF_DIR/,*.conf'"
echo "   and that the Phase 1 host-record lines there are commented out, so only one record set is live."
echo "1. Restart dnsmasq (host-record changes need a restart, not a reload):"
echo "   sudo brew services restart dnsmasq"
echo "2. Verify:"
echo "   dig @$MAC1_IP app.teamX.test +noall +answer   # expect $TARGET_EDGE_IP with TTL $TTL"
