#!/usr/bin/env bash
# ABOUTME: Mac 2 (edge) setup for CN Project Phase 1: team CA, server cert, and nginx load balancer config.
# ABOUTME: Follows steps 5a to 5d of the Mac 2 doc exactly; re-runnable, and never regenerates an existing CA.
#
# Usage: ./mac2-edge-setup.sh <team-number> <MAC3_IP> <MAC4_IP>
#   e.g. ./mac2-edge-setup.sh 7 10.0.0.13 10.0.0.14
# Backend IPs can be the placeholder "pending" until lab day; the cert step still runs.
set -euo pipefail

if [ $# -ne 3 ]; then
  echo "usage: $0 <team-number> <MAC3_IP|pending> <MAC4_IP|pending>" >&2
  exit 1
fi

TEAM="team$1"
MAC3_IP="$2"
MAC4_IP="$3"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PREFIX="$(brew --prefix)"
TLS_DIR="$HOME/cn-project/tls"
CONF="$PREFIX/etc/nginx/servers/$TEAM.conf"
LOG_DIR="$PREFIX/var/log/nginx"

# 5a. OpenSSL 3 from Homebrew (macOS LibreSSL lacks -addext)
export PATH="$(brew --prefix openssl@3)/bin:$PATH"
openssl version | grep -q '^OpenSSL 3' || { echo "need OpenSSL 3.x" >&2; exit 1; }
command -v nginx >/dev/null || { echo "nginx missing: brew install nginx" >&2; exit 1; }
mkdir -p "$TLS_DIR" "$PREFIX/etc/nginx/servers" "$LOG_DIR"
cd "$TLS_DIR"

# 5b. Team root CA. Reissuing it would force every Mac to re-trust, so keep an existing one.
if [ ! -f "$TEAM-rootCA.key" ]; then
  openssl genrsa -out "$TEAM-rootCA.key" 4096
  openssl req -x509 -new -key "$TEAM-rootCA.key" -sha256 -days 365 -out "$TEAM-rootCA.crt" \
    -subj "/CN=$TEAM Local Root CA/O=CN Project $TEAM" \
    -addext "basicConstraints=critical,CA:TRUE" \
    -addext "keyUsage=critical,keyCertSign,cRLSign"
  chmod 600 "$TEAM-rootCA.key"
else
  echo "CA for $TEAM already exists, reusing it"
fi

# 5c. Server certificate for app/api.<team>.test
openssl genrsa -out "app.$TEAM.test.key" 2048
openssl req -new -key "app.$TEAM.test.key" -out "app.$TEAM.test.csr" \
  -subj "/CN=app.$TEAM.test/O=CN Project $TEAM"

cat > "app.$TEAM.test.ext" <<EOF
basicConstraints=CA:FALSE
keyUsage=critical,digitalSignature,keyEncipherment
extendedKeyUsage=serverAuth
subjectAltName=DNS:app.$TEAM.test,DNS:api.$TEAM.test
authorityKeyIdentifier=keyid,issuer
EOF

openssl x509 -req -in "app.$TEAM.test.csr" -CA "$TEAM-rootCA.crt" -CAkey "$TEAM-rootCA.key" \
  -CAcreateserial -out "app.$TEAM.test.crt" -days 365 -sha256 -extfile "app.$TEAM.test.ext"
chmod 600 "app.$TEAM.test.key"

date
openssl verify -CAfile "$TEAM-rootCA.crt" "app.$TEAM.test.crt"
openssl x509 -in "app.$TEAM.test.crt" -noout -subject -issuer -ext subjectAltName

# 5d. nginx server file (Homebrew's nginx.conf includes servers/*)
if [ "$MAC3_IP" = "pending" ] || [ "$MAC4_IP" = "pending" ]; then
  echo "Backend IPs pending: skipping nginx config. Re-run with real IPs on lab day."
  exit 0
fi

cat > "$CONF" <<EOF
# ---- CN Project $TEAM : Mac 2 edge ----
log_format ${TEAM}_lb '\$remote_addr [\$time_local] "\$request" \$status -> upstream=\$upstream_addr (\$upstream_status) \$request_time s';

upstream ${TEAM}_backends {
    # round-robin is nginx's default strategy
    server $MAC3_IP:3001 max_fails=1 fail_timeout=10s;   # Backend A (Trishit)
    server $MAC4_IP:3002 max_fails=1 fail_timeout=10s;   # Backend B (Husain)
}

# plain HTTP -> redirect to HTTPS
server {
    listen 80;
    server_name app.$TEAM.test api.$TEAM.test;
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl;                     # use 8443 if 443 won't bind
    http2 on;
    server_name app.$TEAM.test api.$TEAM.test;

    ssl_certificate     $TLS_DIR/app.$TEAM.test.crt;
    ssl_certificate_key $TLS_DIR/app.$TEAM.test.key;
    ssl_protocols TLSv1.2 TLSv1.3;

    access_log $LOG_DIR/${TEAM}_access.log ${TEAM}_lb;

    location / {
        proxy_pass http://${TEAM}_backends;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_connect_timeout 2s;
        proxy_next_upstream error timeout http_502 http_503;   # retry the other backend if one is down
        add_header X-Edge "mac2-nginx" always;
        add_header X-Upstream-Addr \$upstream_addr always;      # shows which backend IP:port served you
    }
}
EOF

cp "$CONF" "$SCRIPT_DIR/nginx-$TEAM.conf"
cp "$TLS_DIR/$TEAM-rootCA.crt" "$SCRIPT_DIR/"
echo "Wrote $CONF. Next: sudo nginx -t && sudo nginx"
