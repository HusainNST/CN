#!/usr/bin/env bash
# Live demo helper for Mac 3 (Trishit — Backend A, Caching, Backup DNS & pf Isolation).
set -euo pipefail

# shellcheck source=env.sh
source "$(cd "$(dirname "$0")" && pwd)/env.sh"

usage() {
  cat <<EOF
Usage: $(basename "$0") <command>

Commands:
  info              Show Mac 3 IP/MAC/gateway and ping Macs 1, 2, 4
  start-backend     Run Backend A on 0.0.0.0:3001 (Ctrl+C to stop for Demo Step 8)
  check-cache       Demonstrate /api/cached 200+ETag, conditional 304, and /api/status no-store (Demo Step 7)
  setup-backup-dns  Install Phase 2 backup dnsmasq config (pointing to Mac 2) and restart (Ext A)
  cutover-standby   Switch backup DNS records to Mac 4 standby ($MAC4_IP) and restart (Ext E)
  cutover-primary   Switch backup DNS records back to Mac 2 ($MAC2_IP) and restart (Ext E)
  dns-status        Verify backup dnsmasq listener on :53 and query records
  dns-logs          Tail live backup dnsmasq query log
  pf-on             Enable pf isolation on port 3001 allowing Mac 2 and Mac 4 standby (Ext C)
  pf-off            Roll back pf isolation cleanly (Ext C)
  pf-status         Show active rules in teamX-backend anchor
EOF
}

cmd="${1:-}"
case "$cmd" in
  info)
    show_lan_info "Mac 3 (Backend A + Backup DNS)" "$MAC1_IP" "$MAC2_IP" "$MAC4_IP"
    ;;
  start-backend)
    banner "Starting Backend A on 0.0.0.0:3001 (Ctrl+C to stop)"
    BACKEND_ID=A PORT=3001 exec python3 "$REPO_ROOT/03_backend_code/server.py"
    ;;
  check-cache)
    banner "Demo Step 7: HTTP Caching (/api/cached -> 200, then 304, plus /api/status no-store)"
    echo "--- 1. Full GET /api/cached ---"
    "$CURL_BIN" --cacert "$CA_CERT" -sS -i "https://$DOMAIN/api/cached"
    ETAG=$("$CURL_BIN" --cacert "$CA_CERT" -sI "https://$DOMAIN/api/cached" | awk 'tolower($1)=="etag:" {print $2}' | tr -d '\r')
    echo ""
    echo "--- 2. Conditional GET with If-None-Match: $ETAG (expect 304 Not Modified) ---"
    "$CURL_BIN" --cacert "$CA_CERT" -sS -i -H "If-None-Match: $ETAG" "https://$DOMAIN/api/cached"
    echo ""
    echo "--- 3. HEAD /api/status (expect Cache-Control: no-store) ---"
    "$CURL_BIN" --cacert "$CA_CERT" -sI "https://$DOMAIN/api/status" | grep -iE "^HTTP|^cache-control|^x-backend"
    ;;
  setup-backup-dns)
    banner "Configure Mac 3 Backup DNS -> $MAC2_IP (TTL $TTL)"
    "$REPO_ROOT/02_config/phase2/mac3-backup-dns.sh" "$MAC3_IP" "$MAC2_IP" "$TTL"
    sudo brew services restart dnsmasq
    ;;
  cutover-standby)
    banner "Switching Backup DNS -> Mac 4 Standby ($MAC4_IP, TTL $TTL)"
    "$REPO_ROOT/02_config/phase2/mac3-backup-dns.sh" "$MAC3_IP" "$MAC4_IP" "$TTL"
    sudo brew services restart dnsmasq
    dig "@$MAC3_IP" "$DOMAIN" +noall +answer
    ;;
  cutover-primary)
    banner "Rolling Backup DNS Back -> Mac 2 Primary ($MAC2_IP, TTL $TTL)"
    "$REPO_ROOT/02_config/phase2/mac3-backup-dns.sh" "$MAC3_IP" "$MAC2_IP" "$TTL"
    sudo brew services restart dnsmasq
    dig "@$MAC3_IP" "$DOMAIN" +noall +answer
    ;;
  dns-status)
    banner "Mac 3 Backup DNS Listener & Records"
    sudo lsof -nP -i:53
    dig "@$MAC3_IP" "$DOMAIN" +noall +answer
    dig "@$MAC3_IP" "$API_DOMAIN" +noall +answer
    ;;
  dns-logs)
    tail -f "$BREW_PREFIX/var/log/dnsmasq.log"
    ;;
  pf-on)
    banner "Enabling pf Isolation on Mac 3 :3001 (allow lo0, $MAC2_IP, $MAC4_IP)"
    sudo "$REPO_ROOT/02_config/phase2/pf-backend-isolate.sh" 3001 "$MAC2_IP" "$MAC4_IP"
    ;;
  pf-off)
    banner "Rolling Back pf Isolation on Mac 3"
    sudo "$REPO_ROOT/02_config/phase2/pf-backend-rollback.sh"
    ;;
  pf-status)
    sudo pfctl -s info | head -n 2
    sudo pfctl -a teamX-backend -sr
    ;;
  *)
    usage
    exit 1
    ;;
esac
