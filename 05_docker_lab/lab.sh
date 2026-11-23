#!/usr/bin/env bash
# ABOUTME: In-container service control for the emulated Macs (DNS, client DNS cache, backend, nginx, firewall).
# ABOUTME: Configs are always rendered by the repo's 02_config/phase2 scripts so the lab tests the real deliverables.
set -euo pipefail

P2=/repo/02_config/phase2
CONF_DIR=/etc/teamX
LOG_DIR=/usr/local/var/log
mkdir -p "$CONF_DIR" "$LOG_DIR/nginx" /run/teamX
chmod 777 "$LOG_DIR"

dns_conf() { echo "$CONF_DIR/dns.conf"; }

render_dns() {
  # render_dns <edge_ip> : renders this Mac's authoritative dnsmasq config
  local edge="$1"
  case "$ROLE" in
    mac1) bash "$P2/mac1-dns-phase2.sh" --render-only "$(dns_conf)" "$MAC1_IP" "$edge" 30 ;;
    mac3) bash "$P2/mac3-backup-dns.sh" --render-only "$(dns_conf)" "$MAC3_IP" "$edge" 30 ;;
    *) echo "$ROLE does not run an authoritative DNS server" >&2; exit 1 ;;
  esac
}

dns_start() {
  dnsmasq --conf-file="$(dns_conf)" --pid-file=/run/teamX/dns.pid --user=root
  echo "dnsmasq started on $ROLE"
}

dns_stop() {
  if [ -f /run/teamX/dns.pid ] && kill "$(cat /run/teamX/dns.pid)" 2>/dev/null; then
    rm -f /run/teamX/dns.pid
    echo "dnsmasq stopped on $ROLE"
  else
    echo "dnsmasq was not running on $ROLE"
  fi
}

# The client cache plays the part of macOS mDNSResponder: it lists the primary
# and backup resolvers in order, caches answers for their TTL, and is flushed
# with SIGHUP (macOS: sudo killall -HUP mDNSResponder).
cache_start() {
  cat > "$CONF_DIR/client-cache.conf" <<EOF
listen-address=127.0.0.53
bind-interfaces
no-resolv
strict-order
server=$MAC1_IP
server=$MAC3_IP
cache-size=150
EOF
  dnsmasq --conf-file="$CONF_DIR/client-cache.conf" --pid-file=/run/teamX/cache.pid --user=root
  printf 'nameserver 127.0.0.53\noptions timeout:2 attempts:2\n' > /etc/resolv.conf
  echo "client DNS cache started on $ROLE (resolvers: $MAC1_IP then $MAC3_IP)"
}

cache_flush() {
  kill -HUP "$(cat /run/teamX/cache.pid)"
  echo "client DNS cache flushed on $ROLE"
}

backend_start() {
  local id port
  case "$ROLE" in
    mac3) id=A; port=3001 ;;
    mac4) id=B; port=3002 ;;
    *) echo "$ROLE has no backend" >&2; exit 1 ;;
  esac
  BACKEND_ID=$id PORT=$port nohup python3 /repo/03_backend_code/server.py >>/var/log/backend.log 2>&1 &
  echo $! > /run/teamX/backend.pid
  sleep 0.5
  echo "Backend $id started on $ROLE:$port"
}

backend_stop() {
  if [ -f /run/teamX/backend.pid ] && kill "$(cat /run/teamX/backend.pid)" 2>/dev/null; then
    rm -f /run/teamX/backend.pid
    echo "backend stopped on $ROLE"
  else
    echo "backend was not running on $ROLE"
  fi
}

nginx_start() { nginx -t 2>&1 && nginx && echo "nginx started on $ROLE"; }
nginx_stop() { nginx -s quit 2>/dev/null && sleep 0.5; echo "nginx stopped on $ROLE"; }

# Linux stand-in for pf: back up the current rules once, then load the anchor
# rendered by pf-backend-isolate.sh as iptables rules.
fw_isolate() {
  local port="$1"; shift
  local anchor="$CONF_DIR/pf-anchor-$port.conf"
  [ -f /run/teamX/iptables.phase1.bak ] || iptables-save > /run/teamX/iptables.phase1.bak
  bash "$P2/pf-backend-isolate.sh" --render-only "$anchor" "$CONF_DIR/pf.conf" "$port" "$@" >/dev/null
  echo "pf anchor rendered by pf-backend-isolate.sh:"
  sed 's/^/  /' "$anchor"
  pf-anchor-to-iptables "$anchor"
}

fw_rollback() {
  # The backup may lack a filter table (it did not exist yet), and iptables-restore
  # only resets tables present in its input, so remove the anchor chain explicitly.
  while iptables -D INPUT -j TEAMX-BACKEND 2>/dev/null; do :; done
  iptables -F TEAMX-BACKEND 2>/dev/null || true
  iptables -X TEAMX-BACKEND 2>/dev/null || true
  iptables-restore < /run/teamX/iptables.phase1.bak
  rm -f /run/teamX/iptables.phase1.bak
  echo "firewall restored to the saved Phase 1 state on $ROLE"
  iptables -S INPUT
}

cmd="${1:-}"; shift || true
case "$cmd" in
  render-dns) render_dns "$@" ;;
  dns-start) dns_start ;;
  dns-stop) dns_stop ;;
  dns-restart) dns_stop; dns_start ;;
  cache-start) cache_start ;;
  cache-flush) cache_flush ;;
  backend-start) backend_start ;;
  backend-stop) backend_stop ;;
  nginx-start) nginx_start ;;
  nginx-stop) nginx_stop ;;
  fw-isolate) fw_isolate "$@" ;;
  fw-rollback) fw_rollback ;;
  *) echo "usage: lab {render-dns EDGE_IP|dns-start|dns-stop|dns-restart|cache-start|cache-flush|backend-start|backend-stop|nginx-start|nginx-stop|fw-isolate PORT EDGE [STANDBY]|fw-rollback}" >&2; exit 1 ;;
esac
