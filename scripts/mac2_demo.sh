#!/usr/bin/env bash
# Live demo helper for Mac 2 (Sarvesh — Primary HTTPS Edge, Load Balancer & Team CA).
set -euo pipefail

# shellcheck source=env.sh
source "$(cd "$(dirname "$0")" && pwd)/env.sh"

usage() {
  cat <<EOF
Usage: $(basename "$0") <command>

Commands:
  info            Show Mac 2 IP/MAC/gateway and ping Macs 1, 3, 4
  setup           Refresh Phase 2 edge nginx config with current backend IPs and reload
  status          Run nginx -t and verify listeners on TCP 80 and 443
  logs            Tail live nginx load-balancer access log
  check-backends  Curl Backend A ($MAC3_IP:3001) and Backend B ($MAC4_IP:3002) directly (Ext C allow proof)
  check-https     Verify trusted HTTPS by hostname without -k (Demo Step 4)
  check-lb        Send 6 HTTPS requests showing alternating A/B backends (Demo Step 5)
EOF
}

cmd="${1:-}"
case "$cmd" in
  info)
    show_lan_info "Mac 2 (Primary Edge)" "$MAC1_IP" "$MAC3_IP" "$MAC4_IP"
    ;;
  setup)
    banner "Refresh Mac 2 Primary Edge -> Backends $MAC3_IP:3001, $MAC4_IP:3002"
    "$REPO_ROOT/02_config/phase2/mac2-edge-phase2.sh" "$MAC3_IP" "$MAC4_IP"
    sudo nginx -t
    if pgrep -x nginx >/dev/null 2>&1; then
      sudo nginx -s reload
    else
      sudo nginx
    fi
    ;;
  status)
    banner "Mac 2 NGINX Syntax & Listeners"
    sudo nginx -t
    sudo lsof -nP -iTCP:80,443 -sTCP:LISTEN
    ;;
  logs)
    tail -f "$BREW_PREFIX/var/log/nginx/teamX_access.log"
    ;;
  check-backends)
    banner "Direct Backend Reachability from Mac 2 Edge"
    echo "--- Backend A ($MAC3_IP:3001) ---"
    "$CURL_BIN" -sS -i "http://$MAC3_IP:3001/api/status"
    echo ""
    echo "--- Backend B ($MAC4_IP:3002) ---"
    "$CURL_BIN" -sS -i "http://$MAC4_IP:3002/api/status"
    ;;
  check-https)
    banner "Demo Step 4: Trusted HTTPS by Hostname (no -k)"
    "$CURL_BIN" --cacert "$CA_CERT" -v "https://$DOMAIN/api/status"
    ;;
  check-lb)
    check_lb_six
    ;;
  *)
    usage
    exit 1
    ;;
esac
