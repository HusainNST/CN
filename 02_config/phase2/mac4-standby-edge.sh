#!/usr/bin/env bash
# ABOUTME: Mac 4 standby HTTPS edge for CN Project Phase 2 (Extension E): standby key/CSR and nginx config.
# ABOUTME: The CSR is signed on Mac 2; teamX-rootCA.key never leaves Mac 2 and no private key goes in the repo.
# ABOUTME: The standby CSR holds only the public key, so it is committed at 02_config/phase2/app.teamX.test-standby.csr.
#
# Usage:
#   ./mac4-standby-edge.sh --generate-csr [--force]           # key + CSR in ~/cn-project/tls
#   ./mac4-standby-edge.sh [--render-only <OUT_CONF>] <MAC3_IP> # standby nginx config
# Set CN_TLS_DIR to use a TLS directory other than ~/cn-project/tls.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TLS_DIR="${CN_TLS_DIR:-$HOME/cn-project/tls}"
KEY="$TLS_DIR/app.teamX.test-standby.key"
CSR="$TLS_DIR/app.teamX.test-standby.csr"
CRT="$TLS_DIR/app.teamX.test-standby.crt"
ROOT_CA="$SCRIPT_DIR/../teamX-rootCA.crt"
USAGE="usage: $0 --generate-csr [--force] | [--render-only <OUT_CONF>] <MAC3_IP>"

die() { echo "Error: $*" >&2; exit 1; }

valid_ipv4() {
  local IFS=. octet
  [[ "$1" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]] || return 1
  for octet in $1; do
    [[ "$octet" == 0 || "$octet" != 0* ]] && (( octet <= 255 )) || return 1
  done
}

need_openssl3() {
  openssl version 2>/dev/null | grep -q '^OpenSSL 3' || die "need OpenSSL 3.x on PATH"
}

if [ "${1:-}" = "--generate-csr" ]; then
  [ $# -le 2 ] && { [ $# -eq 1 ] || [ "$2" = "--force" ]; } || die "$USAGE"
  need_openssl3
  if [ -e "$KEY" ] && [ "${2:-}" != "--force" ]; then
    die "$KEY already exists; pass --force to replace it"
  fi
  mkdir -p "$TLS_DIR"
  (umask 077 && openssl req -new -newkey rsa:2048 -nodes -keyout "$KEY" -out "$CSR" \
    -subj "/CN=app.teamX.test/O=CN Project teamX" \
    -addext "subjectAltName=DNS:app.teamX.test,DNS:api.teamX.test" 2>/dev/null)
  chmod 600 "$KEY"
  openssl req -in "$CSR" -noout -verify
  openssl req -in "$CSR" -noout -text | grep -E "Subject:|DNS:"
  echo "Send ONLY $CSR to Mac 2 for signing. Keep $KEY on this Mac."
  exit 0
fi

RENDER_ONLY=""
if [ "${1:-}" = "--render-only" ]; then
  [ $# -ge 2 ] || die "$USAGE"
  RENDER_ONLY="$2"
  shift 2
fi
[ $# -eq 1 ] || die "$USAGE"
valid_ipv4 "$1" || die "invalid MAC3_IP: '$1'"
MAC3_IP="$1"

PREFIX="$(brew --prefix 2>/dev/null || echo /opt/homebrew)"
LOG_DIR="$PREFIX/var/log/nginx"

if [ -z "$RENDER_ONLY" ]; then
  [ -f "$CRT" ] && [ -f "$KEY" ] || die "missing $CRT or $KEY (run --generate-csr, then get the CSR signed on Mac 2)"
  need_openssl3
  openssl verify -CAfile "$ROOT_CA" "$CRT" || die "$CRT does not chain to teamX-rootCA"
  command -v nginx >/dev/null || die "nginx not installed"
  OUT="$PREFIX/etc/nginx/servers/teamX.conf"
  mkdir -p "$(dirname "$OUT")" "$LOG_DIR"
else
  OUT="$RENDER_ONLY"
fi

cat > "$OUT" <<EOF
# ---- CN Project teamX : Mac 4 standby edge (Phase 2, Extension E) ----
log_format teamX_lb '\$remote_addr [\$time_local] "\$request" \$status -> upstream=\$upstream_addr (\$upstream_status) \$request_time s';

upstream teamX_backends {
    server $MAC3_IP:3001 max_fails=1 fail_timeout=10s;   # Backend A (Mac 3)
    server 127.0.0.1:3002 max_fails=1 fail_timeout=10s;   # Backend B (local on Mac 4)
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

    ssl_certificate     $CRT;
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
        proxy_next_upstream error timeout http_502 http_503;
        add_header X-Edge "mac4-standby-nginx" always;
        add_header X-Upstream-Addr \$upstream_addr always;
    }
}
EOF

if [ -z "$RENDER_ONLY" ]; then
  mkdir -p "$SCRIPT_DIR/snapshots"
  cp "$OUT" "$SCRIPT_DIR/snapshots/nginx-standby-mac4.conf"
  echo "Wrote $OUT. Next: sudo nginx -t && sudo nginx (or sudo nginx -s reload)"
else
  echo "Rendered $OUT"
fi
