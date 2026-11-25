#!/usr/bin/env bash
# Live demo helper for Mac 1 (Navodit — Primary DNS & Test Client).
set -euo pipefail

# shellcheck source=env.sh
source "$(cd "$(dirname "$0")" && pwd)/env.sh"

usage() {
  cat <<EOF
Usage: $(basename "$0") <command>

Commands:
  info             Show Mac 1 IP/MAC/gateway and ping Macs 2, 3, 4
  setup            Install Phase 2 primary dnsmasq config (pointing to Mac 2) and restart
  status           Verify dnsmasq listener on :53 and query app/api records
  logs             Tail live dnsmasq query log
  stop-dns         Stop primary dnsmasq (Ext A failover demo)
  start-dns        Start primary dnsmasq (Ext A restore)
  cutover-standby  Switch DNS records to Mac 4 standby edge ($MAC4_IP) and restart
  cutover-primary  Switch DNS records back to Mac 2 primary edge ($MAC2_IP) and restart
  check-isolation  Prove direct backend ports 3001/3002 are refused while HTTPS works (Ext C)
  check-lb         Send 6 HTTPS requests showing alternating backends (Ext D / E)
EOF
}

cmd="${1:-}"
case "$cmd" in
  info)
    show_lan_info "Mac 1 (Primary DNS)" "$MAC2_IP" "$MAC3_IP" "$MAC4_IP"
    ;;
  setup)
    banner "Configure Mac 1 Primary DNS -> $MAC2_IP (TTL $TTL)"
    "$REPO_ROOT/02_config/phase2/mac1-dns-phase2.sh" "$MAC1_IP" "$MAC2_IP" "$TTL"
    sudo brew services restart dnsmasq
    ;;
  status)
    banner "Mac 1 DNS Listener & Records"
    sudo lsof -nP -i:53
    dig "@$MAC1_IP" "$DOMAIN" +noall +answer
    dig "@$MAC1_IP" "$API_DOMAIN" +noall +answer
    ;;
  logs)
    tail -f "$BREW_PREFIX/var/log/dnsmasq.log"
    ;;
  stop-dns)
    banner "Stopping Primary DNS on Mac 1 (Ext A Failover)"
    sudo brew services stop dnsmasq
    ;;
  start-dns)
    banner "Starting Primary DNS on Mac 1 (Ext A Restore)"
    sudo brew services start dnsmasq
    dig "@$MAC1_IP" "$DOMAIN" +noall +answer
    ;;
  cutover-standby)
    banner "Switching Primary DNS -> Mac 4 Standby ($MAC4_IP, TTL $TTL)"
    "$REPO_ROOT/02_config/phase2/mac1-dns-phase2.sh" "$MAC1_IP" "$MAC4_IP" "$TTL"
    sudo brew services restart dnsmasq
    dig "@$MAC1_IP" "$DOMAIN" +noall +answer
    ;;
  cutover-primary)
    banner "Rolling Primary DNS Back -> Mac 2 Primary ($MAC2_IP, TTL $TTL)"
    "$REPO_ROOT/02_config/phase2/mac1-dns-phase2.sh" "$MAC1_IP" "$MAC2_IP" "$TTL"
    sudo brew services restart dnsmasq
    dig "@$MAC1_IP" "$DOMAIN" +noall +answer
    ;;
  check-isolation)
    banner "Ext C: Direct Backend Access Should Fail, HTTPS Through Edge Should Succeed"
    echo "--- Direct Backend A ($MAC3_IP:3001) ---"
    nc -vz -G 2 "$MAC3_IP" 3001 || true
    echo "--- Direct Backend B ($MAC4_IP:3002) ---"
    nc -vz -G 2 "$MAC4_IP" 3002 || true
    echo "--- HTTPS via Edge (https://$DOMAIN/api/status) ---"
    "$CURL_BIN" --cacert "$CA_CERT" -sS -i "https://$DOMAIN/api/status" | head -n 12
    ;;
  check-lb)
    check_lb_six
    ;;
  *)
    usage
    exit 1
    ;;
esac
