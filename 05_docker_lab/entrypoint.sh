#!/usr/bin/env bash
# ABOUTME: Boots one emulated Mac: adds the route through Mac 2, sets up lab TLS, renders configs, starts services.
# ABOUTME: Mac 2 owns the throwaway lab root CA; its private key never leaves the mac2 container.
set -euo pipefail

P2=/repo/02_config/phase2
TLS=/root/cn-project/tls
CA_PUB=/shared/ca/teamX-lab-rootCA.crt
export HOME=/root
mkdir -p "$TLS" /shared/ca /shared/outbox

# Routing between subnets goes through Mac 2's two interfaces.
case "$ROLE" in
  mac1) ip route add "$SERVER_LAN" via "$MAC2_CLIENT_IP" ;;
  mac3|mac4) ip route add "$CLIENT_LAN" via "$MAC2_IP" ;;
esac

if [ "$ROLE" = mac2 ] && [ ! -f "$TLS/teamX-rootCA.key" ]; then
  cd "$TLS"
  rm -f "$CA_PUB"
  openssl req -x509 -newkey rsa:2048 -nodes -days 30 -sha256 \
    -keyout teamX-rootCA.key -out teamX-rootCA.crt \
    -subj "/CN=teamX Lab Root CA (Docker emulation)" 2>/dev/null
  openssl req -new -newkey rsa:2048 -nodes -keyout app.teamX.test.key -out app.teamX.test.csr \
    -subj "/CN=app.teamX.test" 2>/dev/null
  printf 'basicConstraints=CA:FALSE\nkeyUsage=critical,digitalSignature,keyEncipherment\nextendedKeyUsage=serverAuth\nsubjectAltName=DNS:app.teamX.test,DNS:api.teamX.test\n' > app.teamX.test.ext
  openssl x509 -req -in app.teamX.test.csr -CA teamX-rootCA.crt -CAkey teamX-rootCA.key \
    -CAcreateserial -out app.teamX.test.crt -days 30 -sha256 -extfile app.teamX.test.ext 2>/dev/null
  chmod 600 ./*.key
  cp teamX-rootCA.crt "$CA_PUB"
  cd /
fi

# Every Mac trusts the team root CA (Phase 1 client trust step).
for _ in $(seq 1 60); do [ -f "$CA_PUB" ] && break; sleep 0.5; done
cp "$CA_PUB" /usr/local/share/ca-certificates/teamX-lab-rootCA.crt
update-ca-certificates >/dev/null 2>&1

case "$ROLE" in
  mac1)
    lab render-dns "$MAC2_CLIENT_IP"
    lab dns-start
    lab cache-start
    ;;
  mac2)
    bash "$P2/mac2-edge-phase2.sh" --render-only /etc/nginx/conf.d/teamX.conf "$MAC3_IP" "$MAC4_IP"
    lab nginx-start
    ;;
  mac3)
    lab backend-start
    lab render-dns "$MAC2_CLIENT_IP"
    lab dns-start
    ;;
  mac4)
    lab backend-start
    lab cache-start
    bash "$P2/mac4-standby-edge.sh" --render-only /etc/teamX/standby.conf "$MAC3_IP"
    ;;
esac

echo "$ROLE ready"
exec sleep infinity
