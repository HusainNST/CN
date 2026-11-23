#!/usr/bin/env bash
# ABOUTME: Tests for the Mac 4 standby edge script (P2-04) and the 4-layer troubleshooting runbook.
# ABOUTME: Covers bad input rejection, standby nginx render, CSR generation/overwrite guard, and runbook layers.
set -uo pipefail

PHASE2_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$PHASE2_DIR/mac4-standby-edge.sh"
RUNBOOK="$PHASE2_DIR/troubleshooting_runbook.md"
TMP="$(mktemp -d /tmp/cn_test_mac4_XXXXXX)"
trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0

ok()   { PASS=$((PASS + 1)); echo "  [PASS] $1"; }
bad()  { FAIL=$((FAIL + 1)); echo "  [FAIL] $1" >&2; }
check() { local name="$1"; shift; if "$@" >/dev/null 2>&1; then ok "$name"; else bad "$name"; fi; }
refuse() { local name="$1"; shift; if "$@" >/dev/null 2>&1; then bad "$name"; else ok "$name"; fi; }
has()  { check "$3" grep -Fq -- "$2" "$1"; }

echo "1. Syntax"
check "bash -n mac4-standby-edge.sh" bash -n "$SCRIPT"

echo "2. Bad input rejection"
refuse "no arguments rejected"          bash "$SCRIPT"
refuse "non-IP rejected"                bash "$SCRIPT" --render-only "$TMP/x.conf" abc
refuse "octet > 255 rejected"           bash "$SCRIPT" --render-only "$TMP/x.conf" 10.7.18.256
refuse "leading-zero octet rejected"    bash "$SCRIPT" --render-only "$TMP/x.conf" 10.7.018.190
refuse "extra argument rejected"        bash "$SCRIPT" --render-only "$TMP/x.conf" 10.7.18.190 10.7.24.166
refuse "--render-only without path"     bash "$SCRIPT" --render-only
refuse "unknown flag rejected"          bash "$SCRIPT" --bogus 10.7.18.190
check  "bad IP writes no file"          test ! -e "$TMP/x.conf"

echo "3. Standby nginx render"
CONF="$TMP/standby.conf"
TLS="$TMP/tls"
check "renders with Mac 3 IP" env CN_TLS_DIR="$TLS" bash "$SCRIPT" --render-only "$CONF" 10.7.18.190
has "$CONF" "server 10.7.18.190:3001 max_fails=1 fail_timeout=10s;" "upstream Backend A on Mac 3:3001"
has "$CONF" "server 127.0.0.1:3002 max_fails=1 fail_timeout=10s;"   "upstream Backend B on loopback:3002"
has "$CONF" 'add_header X-Edge "mac4-standby-nginx" always;'        "X-Edge identifies standby"
has "$CONF" "add_header X-Upstream-Addr"                            "X-Upstream-Addr header kept"
has "$CONF" "http2 on;"                                             "HTTP/2 enabled"
has "$CONF" "ssl_protocols TLSv1.2 TLSv1.3;"                        "TLS 1.2/1.3 only"
has "$CONF" "ssl_certificate     $TLS/app.teamX.test-standby.crt;"  "standby cert path"
has "$CONF" "ssl_certificate_key $TLS/app.teamX.test-standby.key;"  "standby key path"
has "$CONF" "server_name app.teamX.test api.teamX.test;"            "both hostnames served"
has "$CONF" "proxy_next_upstream error timeout http_502 http_503;"  "backend failover kept"
has "$CONF" "proxy_connect_timeout 2s;"                             "connect timeout kept"
has "$CONF" "return 301 https://\$host\$request_uri;"               "HTTP redirects to HTTPS"
refuse "no unexpanded shell vars" grep -Fq '${' "$CONF"
refuse "no mac2 edge label" grep -Fq 'mac2-nginx' "$CONF"

echo "4. Live mode refuses without a signed cert"
refuse "missing standby cert fails" env CN_TLS_DIR="$TMP/empty" bash "$SCRIPT" 10.7.18.190

echo "5. CSR generation"
if openssl version 2>/dev/null | grep -q '^OpenSSL 3'; then
  CSR_DIR="$TMP/csr"
  check "--generate-csr succeeds" env CN_TLS_DIR="$CSR_DIR" bash "$SCRIPT" --generate-csr
  KEY="$CSR_DIR/app.teamX.test-standby.key"; CSR="$CSR_DIR/app.teamX.test-standby.csr"
  check "key is mode 600" test "$(stat -f %Lp "$KEY")" = 600
  check "CSR signature valid" openssl req -in "$CSR" -noout -verify
  openssl req -in "$CSR" -noout -text > "$TMP/csr.txt" 2>/dev/null
  has "$TMP/csr.txt" "CN=app.teamX.test"                       "CSR subject CN"
  has "$TMP/csr.txt" "DNS:app.teamX.test, DNS:api.teamX.test"  "CSR SAN has both hostnames"
  has "$TMP/csr.txt" "Public-Key: (2048 bit)"                  "RSA 2048 key"
  BEFORE="$(openssl pkey -in "$KEY" -pubout 2>/dev/null)"
  refuse "refuses to overwrite existing key" env CN_TLS_DIR="$CSR_DIR" bash "$SCRIPT" --generate-csr
  check "existing key untouched" test "$(openssl pkey -in "$KEY" -pubout 2>/dev/null)" = "$BEFORE"
  check "--force regenerates" env CN_TLS_DIR="$CSR_DIR" bash "$SCRIPT" --generate-csr --force
  check "--force made a new key" test "$(openssl pkey -in "$KEY" -pubout 2>/dev/null)" != "$BEFORE"
else
  echo "  [SKIP] OpenSSL 3 not on PATH"
fi

echo "6. Runbook"
check "runbook exists" test -f "$RUNBOOK"
if [ -f "$RUNBOOK" ]; then
  has "$RUNBOOK" "Layer 1"   "Layer 1 section"
  has "$RUNBOOK" "Layer 2"   "Layer 2 section"
  has "$RUNBOOK" "Layer 3"   "Layer 3 section"
  has "$RUNBOOK" "Layer 4"   "Layer 4 section"
  has "$RUNBOOK" "dig"       "DNS check command"
  has "$RUNBOOK" "pfctl"     "pf check command"
  has "$RUNBOOK" "openssl s_client" "TLS check command"
  has "$RUNBOOK" "curl"      "HTTP check command"
  check "fits on one page (<= 80 lines)" test "$(wc -l < "$RUNBOOK")" -le 80
fi

echo "Result: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
