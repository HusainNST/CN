#!/usr/bin/env bash
# 4-layer troubleshooting check for Extension F (Demo Step 10).
# Works bottom-up: Layer 1 DNS -> Layer 2 Network/TCP -> Layer 3 TLS -> Layer 4 HTTP.
# Stops and highlights the first failing layer so the team can diagnose out loud.
set -euo pipefail

# shellcheck source=env.sh
source "$(cd "$(dirname "$0")" && pwd)/env.sh"

EDGE_IP="${1:-$MAC2_IP}"

banner "Layer 1: DNS (Primary $MAC1_IP, Backup $MAC3_IP)"
echo "--- Configured macOS nameservers ---"
scutil --dns | grep "nameserver\[" | head -n 6 || true

ans1=$(dig +time=2 +tries=1 "@$MAC1_IP" "$DOMAIN" +short | head -n 1 || true)
ans3=$(dig +time=2 +tries=1 "@$MAC3_IP" "$DOMAIN" +short | head -n 1 || true)
ans_sys=$(dig +time=2 +tries=1 "$DOMAIN" +short | head -n 1 || true)

echo "Primary ($MAC1_IP): ${ans1:-NO ANSWER}"
echo "Backup  ($MAC3_IP): ${ans3:-NO ANSWER}"
echo "System resolver:    ${ans_sys:-NO ANSWER}"

if [ -z "$ans_sys" ] || [ "$ans_sys" != "$EDGE_IP" ]; then
  echo "FAIL at Layer 1 (DNS): system resolver returned '${ans_sys:-empty}', expected '$EDGE_IP'."
  echo "Check: primary/backup dnsmasq status, host-record, or flush DNS cache."
  exit 1
fi
if [ "$ans1" != "$ans3" ]; then
  echo "WARN at Layer 1 (DNS): primary ('$ans1') and backup ('$ans3') disagree."
fi
echo "PASS Layer 1 (DNS)"

banner "Layer 2: Network & TCP ($EDGE_IP:443)"
if ! ping -c 2 -W 1000 "$EDGE_IP" >/dev/null 2>&1; then
  echo "FAIL at Layer 2 (Network): ping to $EDGE_IP failed. Check Wi-Fi/DHCP IP."
  exit 1
fi
echo "ping $EDGE_IP: OK"

if ! nc -vz -G 2 "$EDGE_IP" 443 2>&1; then
  echo "FAIL at Layer 2 (TCP): port 443 on $EDGE_IP refused or timed out. Check nginx listener / firewall."
  exit 1
fi
echo "PASS Layer 2 (Network & TCP)"

banner "Layer 3: TLS ($DOMAIN:443)"
tls_out=$("$OPENSSL_BIN" s_client -connect "$DOMAIN:443" -servername "$DOMAIN" -CAfile "$CA_CERT" </dev/null 2>&1 || true)
echo "$tls_out" | grep -E "subject=|issuer=|Verify return code:" || true

if ! echo "$tls_out" | grep -q "Verify return code: 0 (ok)"; then
  echo "FAIL at Layer 3 (TLS): certificate verification failed."
  echo "Check: nginx ssl_certificate/key paths, SANs, or teamX-rootCA trust."
  exit 1
fi
echo "PASS Layer 3 (TLS)"

banner "Layer 4: HTTP, Proxy & Backends"
http_headers=$("$CURL_BIN" --cacert "$CA_CERT" -sS -D - -o /dev/null "https://$DOMAIN/api/status" || true)
echo "$http_headers" | grep -iE "^HTTP|^x-backend|^x-edge|^x-upstream" || true

if ! echo "$http_headers" | grep -qE "^HTTP/[0-9.]+ 200"; then
  echo "FAIL at Layer 4 (HTTP): did not receive HTTP 200 (502/504 means backend or pf issue)."
  exit 1
fi

check_lb_six
echo "PASS Layer 4 (HTTP, Proxy & Backends) — All 4 layers healthy."
