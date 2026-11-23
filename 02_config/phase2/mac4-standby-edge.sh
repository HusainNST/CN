#!/usr/bin/env bash
# ABOUTME: Mac 4 standby nginx edge script (P2-04): creates the local key and CSR, and renders the standby edge config.
# ABOUTME: The private key stays on Mac 4; only the CSR goes to Mac 2 for signing with the team root CA.
#
# Usage:
#   ./mac4-standby-edge.sh --generate-csr [--force]
#   ./mac4-standby-edge.sh [--render-only <OUT_CONF>] <MAC3_IP>
#     e.g. ./mac4-standby-edge.sh 10.7.18.190
set -euo pipefail

USAGE="Usage: $0 --generate-csr [--force]
       $0 [--render-only <OUT_CONF>] <MAC3_IP>"

validate_ipv4() {
  local rx='^([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})$'
  [[ "$1" =~ $rx ]] || return 1
  local octet
  for octet in "${BASH_REMATCH[@]:1}"; do
    (( octet <= 255 )) || return 1
    [[ ${#octet} -eq 1 || "${octet:0:1}" != "0" ]] || return 1
  done
}

TLS_DIR="$HOME/cn-project/tls"
KEY="$TLS_DIR/app.teamX.test-standby.key"
CSR="$TLS_DIR/app.teamX.test-standby.csr"
CERT="$TLS_DIR/app.teamX.test-standby.crt"

if [ "${1:-}" = "--generate-csr" ]; then
  FORCE=0
  if [ $# -eq 2 ] && [ "$2" = "--force" ]; then
    FORCE=1
  elif [ $# -ne 1 ]; then
    echo "$USAGE" >&2
    exit 1
  fi
  if [ -f "$KEY" ] && [ "$FORCE" -ne 1 ]; then
    echo "Error: $KEY already exists. Use --force to replace it (the old certificate will stop matching)." >&2
    exit 1
  fi
  mkdir -p "$TLS_DIR"
  chmod 700 "$TLS_DIR"
  (
    umask 077
    openssl req -new -newkey rsa:2048 -nodes \
      -keyout "$KEY" -out "$CSR" \
      -subj "/CN=app.teamX.test" \
      -addext "subjectAltName=DNS:app.teamX.test,DNS:api.teamX.test" 2>/dev/null
  )
  chmod 600 "$KEY"
  echo "Created private key $KEY (stays on this Mac, never commit or send it)"
  echo "Created CSR $CSR"
  echo ""
  echo "Check it:  openssl req -in $CSR -noout -text | grep -E 'Subject:|DNS:'"
  echo "Send ONLY the .csr to Mac 2 for signing (see 02_config/phase2/standby-tls-notes.md)."
  exit 0
fi

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

if [ $# -ne 1 ]; then
  echo "$USAGE" >&2
  exit 1
fi

MAC3_IP="$1"
validate_ipv4 "$MAC3_IP" || { echo "Error: Invalid MAC3_IP IPv4 address: '$MAC3_IP'" >&2; exit 1; }

if command -v brew >/dev/null 2>&1; then
  BREW_PREFIX="$(brew --prefix)"
elif [ -d /opt/homebrew ]; then
  BREW_PREFIX="/opt/homebrew"
else
  BREW_PREFIX="/usr/local"
fi
LOG_DIR="$BREW_PREFIX/var/log/nginx"

render_nginx_conf() {
  cat <<EOF
# ---- CN Project teamX : Mac 4 standby edge (Phase 2, Extension E) ----
log_format teamX_lb '\$remote_addr [\$time_local] "\$request" \$status -> upstream=\$upstream_addr (\$upstream_status) \$request_time s';

upstream teamX_backends {
    server $MAC3_IP:3001 max_fails=1 fail_timeout=10s;   # Backend A (Mac 3)
    server 127.0.0.1:3002 max_fails=1 fail_timeout=10s;  # Backend B (this Mac)
}

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

    access_log $LOG_DIR/teamX_standby_access.log teamX_lb;

    location / {
        proxy_pass http://teamX_backends;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_connect_timeout 2s;
        proxy_next_upstream error timeout http_502 http_503;
        add_header X-Edge "mac4-standby-nginx" always;
        add_header X-Upstream-Addr \$upstream_addr always;
    }
}
EOF
}

if [ "$RENDER_ONLY" -eq 1 ]; then
  mkdir -p "$(dirname "$OUT_CONF")"
  render_nginx_conf > "$OUT_CONF"
  echo "Rendered standby edge nginx configuration to $OUT_CONF"
  exit 0
fi

for f in "$CERT" "$KEY"; do
  if [ ! -f "$f" ]; then
    echo "Error: $f not found. Generate the CSR, then get Mac 2 to sign it (P2-05) before going live." >&2
    exit 1
  fi
done

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
ROOT_CA="$REPO_ROOT/02_config/teamX-rootCA.crt"
if ! openssl verify -CAfile "$ROOT_CA" "$CERT"; then
  echo "Error: $CERT does not chain to $ROOT_CA. Clients would show a certificate warning." >&2
  exit 1
fi

SNAPSHOT_DIR="$REPO_ROOT/02_config/phase2/snapshots"
LIVE_CONF="$BREW_PREFIX/etc/nginx/servers/teamX-standby.conf"
mkdir -p "$SNAPSHOT_DIR" "$(dirname "$LIVE_CONF")" "$LOG_DIR"
render_nginx_conf > "$LIVE_CONF"
render_nginx_conf > "$SNAPSHOT_DIR/nginx-standby-mac4.conf"
echo "Installed live configuration to $LIVE_CONF"
echo "Exported snapshot to $SNAPSHOT_DIR/nginx-standby-mac4.conf"
echo ""
echo "==== Next Steps on Mac 4 ===="
echo "1. If Mac 3 pf isolation is active, Mac 3 must allow this Mac: sudo pf-backend-isolate.sh 3001 <MAC2_IP> <MAC4_IP>"
echo "2. sudo nginx -t && sudo nginx    (or: sudo nginx -s reload)"
echo "3. lsof -nP -iTCP:443 -sTCP:LISTEN"
