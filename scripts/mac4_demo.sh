#!/usr/bin/env bash
# Live demo helper for Mac 4 (Husain — Backend B, Client, Wireshark, Standby Edge & pf Isolation).
set -euo pipefail

# shellcheck source=env.sh
source "$(cd "$(dirname "$0")" && pwd)/env.sh"

usage() {
  cat <<EOF
Usage: $(basename "$0") <command>

Commands:
  info               Show Mac 4 IP/MAC/gateway and ping Macs 1, 2, 3 (Demo Step 2)
  start-backend      Run Backend B on 0.0.0.0:3002
  check-lb           Send 6 HTTPS requests showing alternating A/B backends
  check-ttl          Compare live DNS (dig) vs macOS cache (dscacheutil) (Ext B)
  flush-dns          Flush macOS DNS cache and immediately re-run check-ttl (Ext B)
  standby-start      Configure and start Mac 4 standby HTTPS edge (Ext E)
  standby-stop       Stop Mac 4 standby HTTPS edge (Ext E rollback)
  pf-on              Enable pf isolation on port 3002 allowing lo0 and Mac 2 (Ext C)
  pf-off             Roll back pf isolation cleanly (Ext C)
  pf-status          Show active rules in teamX-backend anchor
  wireshark-filters  Print Demo Step 6 capture paths and Wireshark display filters
EOF
}

cmd="${1:-}"
case "$cmd" in
  info)
    show_lan_info "Mac 4 (Backend B + Client + Standby Edge)" "$MAC1_IP" "$MAC2_IP" "$MAC3_IP"
    ;;
  start-backend)
    banner "Starting Backend B on 0.0.0.0:3002 (Ctrl+C to stop)"
    BACKEND_ID=B PORT=3002 exec python3 "$REPO_ROOT/03_backend_code/server.py"
    ;;
  check-lb)
    check_lb_six
    ;;
  check-ttl)
    banner "Ext B: Live Resolver (dig) vs macOS Cache (dscacheutil)"
    date
    echo "--- dig $DOMAIN (asks resolver directly) ---"
    dig "$DOMAIN" +noall +answer +comments | grep -E "SERVER:|IN[[:space:]]+A" || true
    echo "--- dscacheutil -q host -a name $DOMAIN (OS cache) ---"
    dscacheutil -q host -a name "$DOMAIN" || true
    ;;
  flush-dns)
    banner "Ext B: Flushing macOS DNS Cache"
    flush_dns_cache
    date
    dscacheutil -q host -a name "$DOMAIN" || true
    ;;
  standby-start)
    banner "Starting Mac 4 Standby Edge (proxying to $MAC3_IP:3001 and 127.0.0.1:3002)"
    "$REPO_ROOT/02_config/phase2/mac4-standby-edge.sh" "$MAC3_IP"
    sudo nginx -t
    if pgrep -x nginx >/dev/null 2>&1; then
      sudo nginx -s reload
    else
      sudo nginx
    fi
    sudo lsof -nP -iTCP:80,443 -sTCP:LISTEN
    ;;
  standby-stop)
    banner "Stopping Mac 4 Standby Edge"
    sudo nginx -s stop
    ;;
  pf-on)
    banner "Enabling pf Isolation on Mac 4 :3002 (allow lo0, $MAC2_IP)"
    sudo "$REPO_ROOT/02_config/phase2/pf-backend-isolate.sh" 3002 "$MAC2_IP"
    ;;
  pf-off)
    banner "Rolling Back pf Isolation on Mac 4"
    sudo "$REPO_ROOT/02_config/phase2/pf-backend-rollback.sh"
    ;;
  pf-status)
    sudo pfctl -s info | head -n 2
    sudo pfctl -a teamX-backend -sr
    ;;
  wireshark-filters)
    cat <<EOF
Saved captures (Demo Step 6):
  TLS 1.2 (cert visible in cleartext): $REPO_ROOT/04_evidence/G_protocol_flow/G_capture3_tls12.pcapng
  TLS 1.3 (cert encrypted):            $REPO_ROOT/04_evidence/G_protocol_flow/G_capture2_tls13.pcapng
  Wrong port 8444 (SYN -> RST, ACK):   $REPO_ROOT/04_evidence/H_failures/H-05_wrong_port.pcapng

Wireshark display filters:
  DNS query/response:  dns
  TCP 3-way handshake: tcp.flags.syn == 1
  TLS handshake:       tls.handshake
  Encrypted HTTP:      tls.app_data
  Wrong port 8444:     tcp.port == 8444
EOF
    ;;
  *)
    usage
    exit 1
    ;;
esac
