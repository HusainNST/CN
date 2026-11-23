#!/usr/bin/env bash
# ABOUTME: Mac 1 parameterized primary dnsmasq script for CN Project Phase 2 (Extensions B and E).
# ABOUTME: Renders teamX.test records with local-ttl (default 30); re-run with a new edge IP to switch records.
#
# Usage: ./mac1-dns-phase2.sh [--render-only <OUT_CONF>] <MAC1_IP> <TARGET_EDGE_IP> [TTL=30]
#   e.g. ./mac1-dns-phase2.sh 10.7.4.108 10.7.6.184
#   e.g. ./mac1-dns-phase2.sh --render-only /tmp/primary-dns.conf 10.7.4.108 10.7.6.184 30
#
# Record switch (Extension B TTL demo, Extension E edge cutover): run again with the
# new TARGET_EDGE_IP, then restart dnsmasq. Both app and api records move together.
# Phase 1's 02_config/dnsmasq-teamX.conf is never read or modified by this script.
set -euo pipefail

USAGE="Usage: $0 [--render-only <OUT_CONF>] <MAC1_IP> <TARGET_EDGE_IP> [TTL=30]"

validate_ipv4() {
  local ip="$1"
  local rx='^([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})$'
  if [[ ! "$ip" =~ $rx ]]; then
    return 1
  fi
  for octet in "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" "${BASH_REMATCH[3]}" "${BASH_REMATCH[4]}"; do
    if [[ ${#octet} -gt 1 && "${octet:0:1}" == "0" ]]; then
      return 1
    fi
    if (( 10#$octet > 255 )); then
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
  if [[ ${#ttl} -gt 1 && "${ttl:0:1}" == "0" ]]; then
    return 1
  fi
  if (( ${#ttl} > 10 )) || (( 10#$ttl < 1 || 10#$ttl > 2147483647 )); then
    return 1
  fi
  return 0
}

RENDER_ONLY=0
OUT_CONF=""

if [ "${1:-}" = "--render-only" ]; then
  if [ $# -lt 2 ] || [ -z "$2" ]; then
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

if ! validate_ipv4 "$MAC1_IP"; then
  echo "Error: Invalid MAC1_IP IPv4 address: '$MAC1_IP'" >&2
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
# ---- CN Project teamX : Mac 1 primary DNS (Phase 2, Extensions B and E) ----
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

# Project A records -> current edge (re-run the script to switch them)
host-record=app.teamX.test,$TARGET_EDGE_IP
host-record=api.teamX.test,$TARGET_EDGE_IP

# TTL for our records, visible in dig's ANSWER section (Extension B)
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

# Live mode: write to Homebrew dnsmasq directory and snapshot export
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SNAPSHOT_DIR="$REPO_ROOT/02_config/phase2/snapshots"
SNAPSHOT_FILE="$SNAPSHOT_DIR/dnsmasq-primary-mac1.conf"
LIVE_CONF_DIR="$BREW_PREFIX/etc/dnsmasq.d"
LIVE_CONF="$LIVE_CONF_DIR/teamX-phase2.conf"
BREW_DNSMASQ_CONF="$BREW_PREFIX/etc/dnsmasq.conf"

if [ ! -f "$BREW_DNSMASQ_CONF" ] || ! grep -Eq '^[[:space:]]*conf-dir=[^#]*dnsmasq\.d/[^,]*,?[[:space:]]*\*\.conf' "$BREW_DNSMASQ_CONF"; then
  echo "Error: $BREW_DNSMASQ_CONF must contain an active conf-dir line for $LIVE_CONF_DIR/*.conf." >&2
  echo "Fix: uncomment or add: conf-dir=$LIVE_CONF_DIR/,*.conf" >&2
  exit 1
fi

if [ ! -x "$BREW_PREFIX/sbin/dnsmasq" ]; then
  echo "Error: $BREW_PREFIX/sbin/dnsmasq not found. Install with: brew install dnsmasq" >&2
  exit 1
fi

# Refuse to install next to another active teamX.test config (for example the
# Phase 1 drop-in): dnsmasq would load both and answer with old and new records.
CONFLICTS=()
for f in "$BREW_DNSMASQ_CONF" "$LIVE_CONF_DIR"/*.conf; do
  [ -f "$f" ] || continue
  [ "$f" = "$LIVE_CONF" ] && continue
  if grep -Eq '^[[:space:]]*(host-record=(app|api)\.teamX\.test|local=/teamX\.test/|local-ttl=)' "$f"; then
    CONFLICTS+=("$f")
  fi
done
if [ ${#CONFLICTS[@]} -gt 0 ]; then
  echo "Error: other active dnsmasq config defines teamX.test records or local-ttl:" >&2
  for f in "${CONFLICTS[@]}"; do
    echo "  $f" >&2
  done
  echo "Move it out of the way first (e.g. mv <file> <file>.phase1.bak), then re-run." >&2
  exit 1
fi

# Validate the rendered config itself before installing it
RENDERED_CONF="$(mktemp "${TMPDIR:-/tmp}/teamX-phase2.XXXXXX")"
trap 'rm -f "$RENDERED_CONF"' EXIT
render_dnsmasq_conf > "$RENDERED_CONF"
if ! "$BREW_PREFIX/sbin/dnsmasq" --test --conf-file="$RENDERED_CONF"; then
  echo "Error: dnsmasq configuration validation failed for the rendered teamX-phase2.conf." >&2
  exit 1
fi

mkdir -p "$SNAPSHOT_DIR" "$BREW_PREFIX/var/log" "$LIVE_CONF_DIR"
cp "$RENDERED_CONF" "$SNAPSHOT_FILE"
echo "Exported snapshot to $SNAPSHOT_FILE"

cp "$RENDERED_CONF" "$LIVE_CONF"
echo "Installed live configuration to $LIVE_CONF"

echo ""
echo "==== Next Steps on Mac 1 ===="
echo "1. Start or restart dnsmasq:"
echo "   sudo brew services restart dnsmasq"
echo "2. Verify dnsmasq listener on port 53:"
echo "   sudo lsof -nP -i:53"
echo "3. Verify records and TTL (expect $TARGET_EDGE_IP and TTL $TTL):"
echo "   dig @$MAC1_IP app.teamX.test +noall +answer"
echo "   dig @$MAC1_IP api.teamX.test +noall +answer"
