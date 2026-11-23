#!/usr/bin/env bash
# ABOUTME: Mac 2 primary nginx Phase 2 script (P2-02): refreshes backend IPs in the edge config.
# ABOUTME: Reuses the existing TLS certificate and key in ~/cn-project/tls and never creates new ones.
#
# Usage: ./mac2-edge-phase2.sh [--render-only <OUT_CONF>] <MAC3_IP> <MAC4_IP>
#   e.g. ./mac2-edge-phase2.sh 10.7.18.190 10.7.24.166
#   e.g. ./mac2-edge-phase2.sh --render-only /tmp/edge.conf 10.7.18.190 10.7.24.166
set -euo pipefail

USAGE="Usage: $0 [--render-only <OUT_CONF>] <MAC3_IP> <MAC4_IP>"

validate_ipv4() {
  local rx='^([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})$'
  [[ "$1" =~ $rx ]] || return 1
  local octet
  for octet in "${BASH_REMATCH[@]:1}"; do
    (( octet <= 255 )) || return 1
    [[ ${#octet} -eq 1 || "${octet:0:1}" != "0" ]] || return 1
  done
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

if [ $# -ne 2 ]; then
  echo "$USAGE" >&2
  exit 1
fi

MAC3_IP="$1"
MAC4_IP="$2"
validate_ipv4 "$MAC3_IP" || { echo "Error: Invalid MAC3_IP IPv4 address: '$MAC3_IP'" >&2; exit 1; }
validate_ipv4 "$MAC4_IP" || { echo "Error: Invalid MAC4_IP IPv4 address: '$MAC4_IP'" >&2; exit 1; }

if command -v brew >/dev/null 2>&1; then
  BREW_PREFIX="$(brew --prefix)"
elif [ -d /opt/homebrew ]; then
  BREW_PREFIX="/opt/homebrew"
else
  BREW_PREFIX="/usr/local"
fi

TLS_DIR="$HOME/cn-project/tls"
CERT="$TLS_DIR/app.teamX.test.crt"
KEY="$TLS_DIR/app.teamX.test.key"
LOG_DIR="$BREW_PREFIX/var/log/nginx"

render_nginx_conf() {
  cat <<EOF
# ---- CN Project teamX : Mac 2 primary edge (Phase 2, Extensions C and D) ----
log_format teamX_lb '\$remote_addr [\$time_local] "\$request" \$status -> upstream=\$upstream_addr (\$upstream_status) \$request_time s';

upstream teamX_backends {
    # round-robin; one failed attempt marks a backend down for 10s (passive health check)
    server $MAC3_IP:3001 max_fails=1 fail_timeout=10s;   # Backend A (Mac 3)
    server $MAC4_IP:3002 max_fails=1 fail_timeout=10s;   # Backend B (Mac 4)
}

# plain HTTP -> redirect to HTTPS
server {
    listen 80;
    server_name app.teamX.test api.teamX.test;
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl;
    http2 on;
    server_name app.teamX.test api.teamX.test;

    ssl_certificate     $CERT;
    ssl_certificate_key $KEY;
    ssl_protocols TLSv1.2 TLSv1.3;

    access_log $LOG_DIR/teamX_access.log teamX_lb;

    location / {
        proxy_pass http://teamX_backends;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_connect_timeout 2s;
        proxy_next_upstream error timeout http_502 http_503;   # retry the other backend if one is down
        add_header X-Edge "mac2-nginx" always;
        add_header X-Upstream-Addr \$upstream_addr always;
    }
}
EOF
}

if [ "$RENDER_ONLY" -eq 1 ]; then
  mkdir -p "$(dirname "$OUT_CONF")"
  render_nginx_conf > "$OUT_CONF"
  echo "Rendered primary edge nginx configuration to $OUT_CONF"
  exit 0
fi

for f in "$CERT" "$KEY"; do
  if [ ! -f "$f" ]; then
    echo "Error: $f not found. Phase 2 reuses the Phase 1 certificate; restore it instead of creating a new one." >&2
    exit 1
  fi
done

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SNAPSHOT_DIR="$REPO_ROOT/02_config/phase2/snapshots"
LIVE_CONF="$BREW_PREFIX/etc/nginx/servers/teamX.conf"

mkdir -p "$SNAPSHOT_DIR" "$(dirname "$LIVE_CONF")" "$LOG_DIR"
render_nginx_conf > "$LIVE_CONF"
render_nginx_conf > "$SNAPSHOT_DIR/nginx-edge-mac2.conf"
echo "Installed live configuration to $LIVE_CONF"
echo "Exported snapshot to $SNAPSHOT_DIR/nginx-edge-mac2.conf"

echo ""
echo "==== Next Steps on Mac 2 ===="
echo "1. sudo nginx -t && sudo nginx -s reload"
echo "2. for i in 1 2 3 4 5 6; do curl -sI https://app.teamX.test/api/status | grep -Ei '^(HTTP|x-backend|x-edge)'; done"
