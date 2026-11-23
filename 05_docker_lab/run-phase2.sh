#!/usr/bin/env bash
# ABOUTME: Runs every Phase 2 extension (A to F) against the Docker emulation and writes timestamped transcripts.
# ABOUTME: Starts from a fresh lab each time so the transcripts are reproducible; they are labelled as emulation evidence.
set -uo pipefail

LAB_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$LAB_DIR/.." && pwd)"
OUT_DIR="$REPO_ROOT/04_evidence/P2_docker_emulation"
SNAP_DIR="$LAB_DIR/snapshots"
cd "$LAB_DIR"
mkdir -p "$OUT_DIR" "$SNAP_DIR"

ip_of() {
  case "$1" in
    mac1) echo 10.77.0.10 ;; mac2) echo "10.77.0.20/10.77.0.70" ;;
    mac3) echo 10.77.0.80 ;; mac4) echo 10.77.0.90 ;;
  esac
}

# run <mac> <command> : prints a prompt line with the container's own clock, then the output
run() {
  local mac="$1"; shift
  local ts
  ts="$(docker compose exec -T "$mac" date '+%Y-%m-%d %H:%M:%S %Z')"
  printf '\n[%s] %s (%s) $ %s\n' "$ts" "$mac" "$(ip_of "$mac")" "$*"
  docker compose exec -T "$mac" bash -c "$*" 2>&1
  local rc=$?
  [ $rc -eq 0 ] || echo "(exit status $rc)"
}

note() { printf '\n## %s\n' "$*"; }
wait_s() { printf '\n(waiting %s seconds: %s)\n' "$1" "$2"; sleep "$1"; }

header() {
  cat <<EOF
DOCKER EMULATION EVIDENCE: not captured on the real Macs.
Four containers stand in for Mac 1 to Mac 4 with the roles from the GitHub issues.
Configs were rendered by the repo's 02_config/phase2 scripts; pf is applied as equivalent iptables rules.
Lab subnets: client LAN 10.77.0.0/26, server LAN 10.77.0.64/26, Mac 2 routes between them.
Mac 1 10.77.0.10 | Mac 2 10.77.0.20 (client side) and 10.77.0.70 (server side) | Mac 3 10.77.0.80 | Mac 4 10.77.0.90
Extension: $1
EOF
}

LOOP6='for i in 1 2 3 4 5 6; do curl -sS -o /dev/null -D - https://app.teamX.test/api/status | tr -d "\r" | grep -Ei "^(HTTP|x-backend|x-edge)" | paste -sd" " -; done'
ONE='curl -sS -o /dev/null -D - https://app.teamX.test/api/status | tr -d "\r" | grep -Ei "^(HTTP|x-backend|x-edge)" | paste -sd" " -'

echo "Resetting the lab..."
docker compose down -v >/dev/null 2>&1
docker compose up -d --build >/dev/null 2>&1 || { echo "docker compose up failed" >&2; exit 1; }
for m in mac1 mac2 mac3 mac4; do
  until docker compose logs "$m" 2>/dev/null | grep -q "$m ready"; do sleep 1; done
done

# ---------------------------------------------------------------- Ext A
{
  header "A, backup DNS resolver (issues P2-07, P2-08, P2-10)"
  note "Primary DNS on Mac 1 (P2-07): rendered by mac1-dns-phase2.sh, TTL 30"
  run mac1 'grep -E "^(listen-address|host-record|local-ttl)" /etc/teamX/dns.conf'
  run mac1 'dig @10.77.0.10 app.teamX.test +noall +answer; dig @10.77.0.10 api.teamX.test +noall +answer'
  note "Backup DNS on Mac 3 (P2-08): rendered by mac3-backup-dns.sh, same records"
  run mac3 'ss -lunp "sport = :53"'
  run mac3 'dig @10.77.0.80 app.teamX.test +noall +answer'
  note "Mac 4 client lists both resolvers, primary first (P2-10, P2A-03)"
  run mac4 'grep -E "^(server|strict-order)" /etc/teamX/client-cache.conf; cat /etc/resolv.conf'
  run mac4 'lab cache-flush; dig app.teamX.test +noall +answer; '"$ONE"
  run mac1 'tail -n 2 /usr/local/var/log/dnsmasq.log'
  note "Stop the primary (Mac 1 dnsmasq) and resolve again from Mac 4 (P2A-04)"
  run mac1 'lab dns-stop'
  run mac4 'dig @10.77.0.10 app.teamX.test +tries=1 +time=2'
  run mac4 'lab cache-flush; dig app.teamX.test +noall +answer; '"$ONE"
  run mac3 'tail -n 4 /usr/local/var/log/dnsmasq.log'
  note "Restore the primary (P2A-05)"
  run mac1 'lab dns-start'
  run mac4 'lab cache-flush; dig app.teamX.test +noall +answer'
  run mac1 'tail -n 2 /usr/local/var/log/dnsmasq.log'
  note "DNS failure versus application failure"
  run mac1 'lab dns-stop'
  run mac3 'lab dns-stop'
  run mac4 'lab cache-flush; '"$ONE"
  run mac1 'lab dns-start'
  run mac3 'lab dns-start'
  run mac3 'lab backend-stop'
  run mac4 'lab backend-stop'
  run mac4 'lab cache-flush; dig app.teamX.test +short; curl -sS -o /dev/null -w "HTTP %{http_code} from %{remote_ip}\n" https://app.teamX.test/api/status'
  run mac3 'lab backend-start'
  run mac4 'lab backend-start'
} > "$OUT_DIR/P2A_backup_dns.txt"
echo "Ext A done"

# ---------------------------------------------------------------- Ext B
{
  header "B, DNS TTL and controlled record change (issue P2-10)"
  echo "Client cache: Mac 4 runs a caching stub that plays the part of macOS mDNSResponder."
  echo "'getent hosts' goes through that cache (macOS: dscacheutil -q host); 'dig @<server>' asks the server directly."
  echo "Flush: SIGHUP to the cache (macOS: sudo dscacheutil -flushcache && sudo killall -HUP mDNSResponder)."
  note "Initial answer with TTL 30 (P2B-01)"
  run mac4 'lab cache-flush; getent hosts app.teamX.test; dig app.teamX.test +noall +answer'
  note "Change app.teamX.test to 10.77.0.90 on Mac 1 and Mac 3 in lockstep"
  run mac1 'lab render-dns 10.77.0.90 && lab dns-restart'
  run mac3 'lab render-dns 10.77.0.90 && lab dns-restart'
  note "Cached old answer until the TTL runs out, then the new one (P2B-02)"
  for _ in 1 2 3 4 5 6 7; do
    run mac4 'echo "cache=$(getent hosts app.teamX.test | cut -d" " -f1)  remaining_ttl=$(dig app.teamX.test +noall +answer | awk "{print \$2}")  server_says=$(dig @10.77.0.10 app.teamX.test +short)"'
    sleep 5
  done
  note "Manual flush gives the new answer immediately (P2B-03)"
  run mac1 'lab render-dns 10.77.0.20 && lab dns-restart'
  run mac3 'lab render-dns 10.77.0.20 && lab dns-restart'
  run mac4 'echo "before flush: $(getent hosts app.teamX.test)"; lab cache-flush; echo "after flush:  $(getent hosts app.teamX.test)"'
  note "Both resolvers restored to Mac 2"
  run mac4 'dig @10.77.0.10 app.teamX.test +short; dig @10.77.0.80 app.teamX.test +short'
} > "$OUT_DIR/P2B_dns_ttl.txt"
echo "Ext B done"

# ---------------------------------------------------------------- Ext C
{
  header "C, backend service isolation (issues P2-11, P2-12, P2-13, P2-14)"
  note "Before isolation: a client can reach the backends directly"
  run mac1 'curl -sS -m 3 http://10.77.0.80:3001/api/status | head -3'
  note "Mac 3 isolates port 3001, only Mac 2's server side IP allowed (P2C-01)"
  run mac3 'lab fw-isolate 3001 10.77.0.70'
  note "Mac 4 isolates port 3002 (P2C-02)"
  run mac4 'lab fw-isolate 3002 10.77.0.70'
  note "Mac 1 client: direct backend ports refused with RST, HTTPS through the edge works (P2C-03)"
  run mac1 'curl -sS -m 3 http://10.77.0.80:3001/api/status'
  run mac1 'curl -sS -m 3 http://10.77.0.90:3002/api/status'
  run mac1 "$ONE"
  note "Mac 4 is on the same subnet as Mac 3 and is still refused on 3001"
  run mac4 'curl -sS -m 3 http://10.77.0.80:3001/api/status'
  note "Mac 2 edge can still reach both backends directly (P2C-04)"
  run mac2 'curl -sS -m 3 -w "  -> HTTP %{http_code}\n" -o /dev/null http://10.77.0.80:3001/api/status; curl -sS -m 3 -w "  -> HTTP %{http_code}\n" -o /dev/null http://10.77.0.90:3002/api/status'
  run mac3 'iptables -L TEAMX-BACKEND -v -n'
  note "Rollback on both backends (P2C-05, P2C-06)"
  run mac3 'lab fw-rollback'
  run mac4 'lab fw-rollback'
  run mac1 'curl -sS -m 3 -w "  -> HTTP %{http_code}\n" -o /dev/null http://10.77.0.80:3001/api/status'
} > "$OUT_DIR/P2C_service_isolation.txt"
echo "Ext C done"

# ---------------------------------------------------------------- Ext D
{
  header "D, high availability failover (issues P2-13, P2-14)"
  echo "nginx upstream: max_fails=1 fail_timeout=10s, proxy_next_upstream error timeout http_502 http_503"
  note "Both backends up (P2D-01)"
  run mac1 "$LOOP6"
  note "Stop Backend A on Mac 3 (P2D-02)"
  run mac3 'lab backend-stop'
  run mac1 "$LOOP6"
  note "Restart Backend A, wait past fail_timeout (P2D-03)"
  run mac3 'lab backend-start'
  wait_s 11 "fail_timeout=10s must expire before nginx retries A"
  run mac1 "$LOOP6"
  note "Mac 2 edge access log across stop and recovery (P2D-04)"
  run mac2 'tail -n 20 /usr/local/var/log/nginx/teamX_access.log'
} > "$OUT_DIR/P2D_ha_failover.txt"
echo "Ext D done"

# ---------------------------------------------------------------- Ext E
{
  header "E, controlled edge migration by DNS cutover (issues P2-04, P2-05, P2-15, P2-16)"
  note "Mac 4 creates its own key and CSR with mac4-standby-edge.sh (P2-04); only the CSR leaves Mac 4"
  run mac4 'bash /repo/02_config/phase2/mac4-standby-edge.sh --generate-csr && ls -l /root/cn-project/tls && cp /root/cn-project/tls/app.teamX.test-standby.csr /shared/outbox/'
  note "Mac 2 signs it with the team root CA, commands from standby-tls-notes.md (P2-05)"
  run mac2 'cd /root/cn-project/tls && printf "basicConstraints=CA:FALSE\nkeyUsage=critical,digitalSignature,keyEncipherment\nextendedKeyUsage=serverAuth\nsubjectAltName=DNS:app.teamX.test,DNS:api.teamX.test\n" > app.teamX.test-standby.ext && openssl x509 -req -in /shared/outbox/app.teamX.test-standby.csr -CA teamX-rootCA.crt -CAkey teamX-rootCA.key -CAserial teamX-rootCA.srl -out app.teamX.test-standby.crt -days 30 -sha256 -extfile app.teamX.test-standby.ext && openssl verify -CAfile teamX-rootCA.crt app.teamX.test-standby.crt && openssl x509 -in app.teamX.test-standby.crt -noout -subject -issuer -ext subjectAltName && cp app.teamX.test-standby.crt /shared/outbox/'
  note "Mac 4 installs the certificate and starts the standby edge (P2E-01)"
  run mac4 'cp /shared/outbox/app.teamX.test-standby.crt /root/cn-project/tls/ && openssl verify -CAfile /shared/ca/teamX-lab-rootCA.crt /root/cn-project/tls/app.teamX.test-standby.crt && cp /etc/teamX/standby.conf /etc/nginx/conf.d/teamX-standby.conf && lab nginx-start && ss -ltnp "sport = :443"'
  note "Before cutover: Mac 1 warms its cache on the Mac 2 edge (P2E-02)"
  run mac1 'lab cache-flush; getent hosts app.teamX.test; '"$ONE"
  note "Cutover: app.teamX.test -> Mac 4 (10.77.0.90) on both DNS servers"
  run mac1 'lab render-dns 10.77.0.90 && lab dns-restart'
  run mac3 'lab render-dns 10.77.0.90 && lab dns-restart'
  note "Inside the TTL window: cached Mac 1 still hits Mac 2, a fresh lookup hits the standby (P2E-03)"
  run mac1 'echo "Mac 1 cache says: $(getent hosts app.teamX.test)"; dig app.teamX.test +noall +answer; '"$ONE"
  run mac4 'lab cache-flush; echo "Mac 4 fresh lookup: $(getent hosts app.teamX.test)"; '"$ONE"
  wait_s 31 "Mac 1 cached answer expires (TTL 30)"
  note "After expiry: Mac 1 now uses the standby edge, with trusted TLS and A/B balancing (P2E-04)"
  run mac1 'getent hosts app.teamX.test; curl -sS -o /dev/null -w "TLS verify result %{ssl_verify_result} (0 = trusted)\n" https://app.teamX.test/api/status; '"$LOOP6"
  note "Rollback to Mac 2 (P2E-05)"
  run mac1 'lab render-dns 10.77.0.20 && lab dns-restart'
  run mac3 'lab render-dns 10.77.0.20 && lab dns-restart'
  run mac4 'lab nginx-stop; rm -f /etc/nginx/conf.d/teamX-standby.conf'
  run mac1 'lab cache-flush; getent hosts app.teamX.test; '"$ONE"
} > "$OUT_DIR/P2E_edge_migration.txt"
echo "Ext E done"

# ---------------------------------------------------------------- Ext F
{
  header "F, troubleshooting drills (issue P2-17). Faults were injected by script, so these drills are not blind."
  note "Drill 1: fault injected on Mac 1 (wrong A record)"
  run mac1 'lab render-dns 10.77.0.30 >/dev/null && lab dns-restart >/dev/null && echo "fault injected"'
  run mac1 'lab cache-flush >/dev/null; curl -sS -m 4 https://app.teamX.test/api/status'
  note "Layer 1 DNS"
  run mac1 'dig app.teamX.test +noall +answer; dig @10.77.0.10 app.teamX.test +short; dig @10.77.0.80 app.teamX.test +short'
  echo "Finding: primary answers 10.77.0.30, backup answers 10.77.0.20 (the edge). Fault is the A record on Mac 1."
  note "Fix and verify"
  run mac1 'lab render-dns 10.77.0.20 >/dev/null && lab dns-restart >/dev/null && lab cache-flush >/dev/null; dig app.teamX.test +short; '"$ONE"

  note "Drill 2: fault injected on Mac 3 (pf allows the wrong edge IP)"
  run mac3 'lab fw-isolate 3001 10.77.0.71 >/dev/null && echo "fault injected"'
  run mac1 "$LOOP6"
  echo "Symptom: every request succeeds but only Backend B answers. Failover is hiding a broken backend path."
  note "Layer 1 DNS"
  run mac1 'dig app.teamX.test +short'
  note "Layer 2 network and TCP, from the edge"
  run mac2 'nc -vz -w 2 10.77.0.80 3001; nc -vz -w 2 10.77.0.90 3002'
  run mac3 'iptables -S TEAMX-BACKEND'
  echo "Finding: Mac 3 accepts 3001 only from 10.77.0.71; the edge's server side IP is 10.77.0.70, so it gets RST."
  note "Fix and verify"
  run mac3 'lab fw-rollback >/dev/null && lab fw-isolate 3001 10.77.0.70 | tail -n 4'
  wait_s 11 "fail_timeout=10s"
  run mac1 "$LOOP6"
  run mac3 'lab fw-rollback | head -n 1'
} > "$OUT_DIR/P2F_troubleshooting_drills.txt"
echo "Ext F done"

# ---------------------------------------------------------------- snapshots
docker compose exec -T mac1 cat /etc/teamX/dns.conf > "$SNAP_DIR/dnsmasq-primary-mac1.conf"
docker compose exec -T mac3 cat /etc/teamX/dns.conf > "$SNAP_DIR/dnsmasq-backup-mac3.conf"
docker compose exec -T mac2 cat /etc/nginx/conf.d/teamX.conf > "$SNAP_DIR/nginx-edge-mac2.conf"
docker compose exec -T mac4 cat /etc/teamX/standby.conf > "$SNAP_DIR/nginx-standby-mac4.conf"
docker compose exec -T mac3 cat /etc/teamX/pf-anchor-3001.conf > "$SNAP_DIR/pf-mac3-3001.conf"
docker compose exec -T mac4 cat /etc/teamX/pf-anchor-3002.conf > "$SNAP_DIR/pf-mac4-3002.conf"
echo "Transcripts in $OUT_DIR, config snapshots in $SNAP_DIR"
