#!/usr/bin/env bash
# ABOUTME: Shared backend pf isolation script for CN Project Phase 2 (Extension C).
# ABOUTME: Restricts direct access to backend port so only designated edge IPs can connect.
#
# Usage: ./pf-backend-isolate.sh [--render-only <OUT_ANCHOR> <OUT_PFCONF>] <PORT> <PRIMARY_EDGE_IP> [STANDBY_EDGE_IP]
#   e.g. sudo ./pf-backend-isolate.sh 3001 10.7.22.227
#   e.g. sudo ./pf-backend-isolate.sh 3002 10.7.22.227 10.7.3.254
#   e.g. ./pf-backend-isolate.sh --render-only /tmp/anchor.conf /tmp/pf.conf 3001 10.7.22.227
set -euo pipefail

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

validate_port() {
  local port="$1"
  if [[ ! "$port" =~ ^[0-9]+$ ]]; then
    return 1
  fi
  if [[ ${#port} -gt 1 && "${port:0:1}" == "0" ]]; then
    return 1
  fi
  if (( 10#$port < 1 || 10#$port > 65535 )); then
    return 1
  fi
  return 0
}

ensure_anchor_in_pfconf() {
  local conf_file="$1"
  if [ ! -f "$conf_file" ]; then
    mkdir -p "$(dirname "$conf_file")"
    echo 'anchor "teamX-backend"' > "$conf_file"
  elif ! grep -Eq '^[[:space:]]*anchor "teamX-backend"[[:space:]]*$' "$conf_file"; then
    if [ -s "$conf_file" ] && [ "$(tail -c 1 "$conf_file" | wc -l)" -eq 0 ]; then
      echo "" >> "$conf_file"
    fi
    echo 'anchor "teamX-backend"' >> "$conf_file"
  fi
  if [ "$conf_file" = "/etc/pf.conf" ] && ! grep -Eq '^[[:space:]]*load anchor "teamX-backend" from "/etc/pf\.anchors/teamX-backend"[[:space:]]*$' "$conf_file"; then
    echo 'load anchor "teamX-backend" from "/etc/pf.anchors/teamX-backend"' >> "$conf_file"
  fi
}

RENDER_ONLY=0
OUT_ANCHOR=""
OUT_PFCONF=""

if [ "${1:-}" = "--render-only" ]; then
  if [ $# -lt 3 ]; then
    echo "Error: --render-only requires <OUT_ANCHOR> and <OUT_PFCONF> file paths." >&2
    echo "Usage: $0 [--render-only <OUT_ANCHOR> <OUT_PFCONF>] <PORT> <PRIMARY_EDGE_IP> [STANDBY_EDGE_IP]" >&2
    exit 1
  fi
  RENDER_ONLY=1
  OUT_ANCHOR="$2"
  OUT_PFCONF="$3"
  shift 3
fi

if [ $# -lt 2 ] || [ $# -gt 3 ]; then
  echo "Usage: $0 [--render-only <OUT_ANCHOR> <OUT_PFCONF>] <PORT> <PRIMARY_EDGE_IP> [STANDBY_EDGE_IP]" >&2
  exit 1
fi

PORT="$1"
PRIMARY_EDGE_IP="$2"
STANDBY_EDGE_IP="${3:-}"

if ! validate_port "$PORT"; then
  echo "Error: Invalid port: '$PORT' (must be between 1 and 65535)" >&2
  exit 1
fi

if ! validate_ipv4 "$PRIMARY_EDGE_IP"; then
  echo "Error: Invalid PRIMARY_EDGE_IP IPv4 address: '$PRIMARY_EDGE_IP'" >&2
  exit 1
fi

if [ -n "$STANDBY_EDGE_IP" ] && ! validate_ipv4 "$STANDBY_EDGE_IP"; then
  echo "Error: Invalid STANDBY_EDGE_IP IPv4 address: '$STANDBY_EDGE_IP'" >&2
  exit 1
fi

render_anchor_rules() {
  cat <<EOF
# ---- teamX-backend PF anchor rules ----
pass in quick on lo0 proto tcp to any port $PORT
pass in quick proto tcp from $PRIMARY_EDGE_IP to any port $PORT
EOF
  if [ -n "$STANDBY_EDGE_IP" ]; then
    cat <<EOF
pass in quick proto tcp from $STANDBY_EDGE_IP to any port $PORT
EOF
  fi
  cat <<EOF
block return-rst in quick proto tcp to any port $PORT
EOF
}

if [ "$RENDER_ONLY" -eq 1 ]; then
  mkdir -p "$(dirname "$OUT_ANCHOR")"
  render_anchor_rules > "$OUT_ANCHOR"
  ensure_anchor_in_pfconf "$OUT_PFCONF"
  echo "Rendered PF anchor rules to $OUT_ANCHOR"
  echo "Ensured anchor \"teamX-backend\" in $OUT_PFCONF"
  exit 0
fi

# Live mode requires root privileges
if [ "${EUID:-$(id -u)}" -ne 0 ]; then
  echo "Error: Live mode must be run with sudo (or as root)." >&2
  exit 1
fi

# Resolve target user's home directory even when invoked with sudo
TARGET_HOME="${HOME}"
if [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ]; then
  USER_HOME="$(eval echo "~$SUDO_USER")"
  if [ -d "$USER_HOME" ]; then
    TARGET_HOME="$USER_HOME"
  fi
fi

BACKUP_DIR="$TARGET_HOME/cn-project"
PF_BAK="$BACKUP_DIR/pf.conf.phase1.bak"
PF_STATE="$BACKUP_DIR/pf.state.phase1"

mkdir -p "$BACKUP_DIR"
if [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ]; then
  chown "$SUDO_USER" "$BACKUP_DIR" 2>/dev/null || true
fi

# Save untouched backup ONLY once (never overwrite existing backup)
if [ ! -f "$PF_BAK" ]; then
  if [ -f "/etc/pf.conf" ]; then
    cp /etc/pf.conf "$PF_BAK"
    if [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ]; then
      chown "$SUDO_USER" "$PF_BAK" 2>/dev/null || true
    fi
    echo "Saved original pf.conf to $PF_BAK"
  else
    echo "Warning: /etc/pf.conf not found to backup" >&2
  fi
else
  echo "Backup $PF_BAK already exists; preserving untouched."
fi

# Save original pf state ONLY once
if [ ! -f "$PF_STATE" ]; then
  if pfctl -s info 2>/dev/null | grep -qi "Status: Enabled"; then
    echo "enabled" > "$PF_STATE"
  else
    echo "disabled" > "$PF_STATE"
  fi
  if [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ]; then
    chown "$SUDO_USER" "$PF_STATE" 2>/dev/null || true
  fi
  echo "Saved original pf state ($(cat "$PF_STATE")) to $PF_STATE"
else
  echo "State file $PF_STATE already exists; preserving untouched."
fi

# Appends anchor "teamX-backend" idempotently to /etc/pf.conf
ensure_anchor_in_pfconf "/etc/pf.conf"
echo "Ensured anchor \"teamX-backend\" in /etc/pf.conf"

# Export snapshot
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SNAPSHOT_DIR="$REPO_ROOT/02_config/phase2/snapshots"
mkdir -p "$SNAPSHOT_DIR"
ANCHOR_FILE="/etc/pf.anchors/teamX-backend"
mkdir -p "$(dirname "$ANCHOR_FILE")"
render_anchor_rules > "$ANCHOR_FILE"

if [ "$PORT" -eq 3001 ]; then
  SNAPSHOT_FILE="$SNAPSHOT_DIR/pf-mac3-3001.conf"
elif [ "$PORT" -eq 3002 ]; then
  SNAPSHOT_FILE="$SNAPSHOT_DIR/pf-mac4-3002.conf"
else
  SNAPSHOT_FILE="$SNAPSHOT_DIR/pf-$PORT.conf"
fi

# Reload /etc/pf.conf and load the teamX-backend anchor
pfctl -f /etc/pf.conf
if ! pfctl -a teamX-backend -sr 2>/dev/null | grep -q "port = $PORT"; then
  echo "Error: teamX-backend anchor has no rules for port $PORT after reload." >&2
  exit 1
fi
if ! pfctl -sr | grep -Eq '^[[:space:]]*anchor "teamX-backend"'; then
  echo "Error: teamX-backend anchor was not loaded into the main pf ruleset." >&2
  exit 1
fi

render_anchor_rules > "$SNAPSHOT_FILE"
if [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ]; then
  chown "$SUDO_USER" "$SNAPSHOT_DIR" "$SNAPSHOT_FILE" 2>/dev/null || true
fi
echo "Exported anchor snapshot to $SNAPSHOT_FILE"

# Enable pf if not already enabled
pfctl -e 2>/dev/null || true

echo ""
echo "==== PF Anchor teamX-backend Loaded Successfully ===="
echo "Active rules in anchor teamX-backend:"
pfctl -a teamX-backend -sr || true
echo ""
echo "To verify backup file:"
echo "  ls -l $PF_BAK"
