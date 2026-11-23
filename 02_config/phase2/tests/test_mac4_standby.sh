#!/usr/bin/env bash
# ABOUTME: Test suite for the Mac 4 standby edge script and troubleshooting runbook (P2-04).
# ABOUTME: Checks input validation, standby nginx render, local key and CSR generation, overwrite refusal, and runbook layers.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PHASE2_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
STANDBY="$PHASE2_DIR/mac4-standby-edge.sh"
RUNBOOK="$PHASE2_DIR/troubleshooting_runbook.md"

TMP_DIR="$(mktemp -d /tmp/cn_test_mac4_XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT

TOTAL=0
FAILED=0
pass() { TOTAL=$((TOTAL + 1)); echo "  [PASS] $1"; }
fail() { TOTAL=$((TOTAL + 1)); FAILED=$((FAILED + 1)); echo "  [FAIL] $1: $2" >&2; }

assert_contains() {
  if grep -Fq -- "$2" "$1"; then pass "$3"; else fail "$3" "'$2' not found in $1"; fi
}
assert_rejects() {
  local name="$1"; shift
  local out="$TMP_DIR/rejected.conf"
  rm -f "$out"
  if bash "$STANDBY" --render-only "$out" "$@" >/dev/null 2>&1; then
    fail "$name" "script exited 0 for bad input: $*"
  elif [ -e "$out" ]; then
    fail "$name" "script wrote $out before rejecting bad input"
  else
    pass "$name"
  fi
}

echo "=========================================================="
echo "Running test suite: Mac 4 standby edge and runbook (P2-04)"
echo "=========================================================="

if [ ! -f "$STANDBY" ]; then
  fail "Script exists" "$STANDBY is missing"
  echo "Test Summary: $((TOTAL - FAILED)) / $TOTAL passed ($FAILED failed)"
  exit 1
fi

if bash -n "$STANDBY"; then pass "bash -n syntax check"; else fail "bash -n syntax check" "syntax error"; fi

echo "-- input validation"
assert_rejects "Rejects missing MAC3_IP"
assert_rejects "Rejects bad MAC3_IP" 10.7.18.256
assert_rejects "Rejects hostname instead of IP" mac3.local
assert_rejects "Rejects too many arguments" 10.7.18.190 10.7.24.166

echo "-- standby nginx render"
CONF="$TMP_DIR/standby.conf"
if HOME="$TMP_DIR/home" bash "$STANDBY" --render-only "$CONF" 10.7.18.190 >/dev/null; then
  pass "Render exits 0"
else
  fail "Render exits 0" "non-zero exit"
fi
assert_contains "$CONF" "server 10.7.18.190:3001 max_fails=1 fail_timeout=10s;" "Standby proxies to Backend A on Mac 3"
assert_contains "$CONF" "server 127.0.0.1:3002 max_fails=1 fail_timeout=10s;" "Standby proxies to local Backend B"
assert_contains "$CONF" 'add_header X-Edge "mac4-standby-nginx" always;' "Standby X-Edge header"
assert_contains "$CONF" "http2 on;" "HTTP/2 enabled"
assert_contains "$CONF" "ssl_protocols TLSv1.2 TLSv1.3;" "TLS versions"
assert_contains "$CONF" "proxy_next_upstream error timeout http_502 http_503;" "Same failover retry as primary"
assert_contains "$CONF" "ssl_certificate     $TMP_DIR/home/cn-project/tls/app.teamX.test-standby.crt;" "Standby certificate path"
assert_contains "$CONF" "ssl_certificate_key $TMP_DIR/home/cn-project/tls/app.teamX.test-standby.key;" "Standby key path"

echo "-- key and CSR generation"
CSR_HOME="$TMP_DIR/csr-home"
TLS="$CSR_HOME/cn-project/tls"
if HOME="$CSR_HOME" bash "$STANDBY" --generate-csr >/dev/null 2>&1; then
  pass "--generate-csr exits 0"
else
  fail "--generate-csr exits 0" "non-zero exit"
fi
if [ -f "$TLS/app.teamX.test-standby.key" ] && [ -f "$TLS/app.teamX.test-standby.csr" ]; then
  pass "Key and CSR created in ~/cn-project/tls"
else
  fail "Key and CSR created in ~/cn-project/tls" "files missing"
fi
PERM="$(stat -f '%Lp' "$TLS/app.teamX.test-standby.key" 2>/dev/null || stat -c '%a' "$TLS/app.teamX.test-standby.key")"
if [ "$PERM" = "600" ]; then pass "Key is chmod 600"; else fail "Key is chmod 600" "mode is $PERM"; fi
openssl req -in "$TLS/app.teamX.test-standby.csr" -noout -text > "$TMP_DIR/csr.txt"
assert_contains "$TMP_DIR/csr.txt" "CN=app.teamX.test" "CSR subject CN is app.teamX.test"
assert_contains "$TMP_DIR/csr.txt" "DNS:app.teamX.test" "CSR SAN has app.teamX.test"
assert_contains "$TMP_DIR/csr.txt" "DNS:api.teamX.test" "CSR SAN has api.teamX.test"
assert_contains "$TMP_DIR/csr.txt" "Public-Key: (2048 bit)" "CSR key is RSA 2048"

KEY_SUM="$(shasum "$TLS/app.teamX.test-standby.key")"
if HOME="$CSR_HOME" bash "$STANDBY" --generate-csr >/dev/null 2>&1; then
  fail "Refuses to overwrite an existing key" "exited 0"
elif [ "$KEY_SUM" = "$(shasum "$TLS/app.teamX.test-standby.key")" ]; then
  pass "Refuses to overwrite an existing key"
else
  fail "Refuses to overwrite an existing key" "key changed"
fi
if HOME="$CSR_HOME" bash "$STANDBY" --generate-csr --force >/dev/null 2>&1 \
  && [ "$KEY_SUM" != "$(shasum "$TLS/app.teamX.test-standby.key")" ]; then
  pass "--force replaces the key"
else
  fail "--force replaces the key" "key not replaced"
fi

echo "-- live mode refuses to run without the signed standby certificate"
if HOME="$TMP_DIR/empty-home" bash "$STANDBY" 10.7.18.190 >"$TMP_DIR/live.out" 2>&1; then
  fail "Live mode fails when standby certificate is missing" "exited 0"
else
  assert_contains "$TMP_DIR/live.out" "app.teamX.test-standby.crt" "Live mode names the missing certificate"
fi

echo "-- troubleshooting runbook"
if [ -f "$RUNBOOK" ]; then
  pass "Runbook exists"
  assert_contains "$RUNBOOK" "Layer 1" "Runbook has Layer 1"
  assert_contains "$RUNBOOK" "DNS" "Runbook covers DNS"
  assert_contains "$RUNBOOK" "Layer 2" "Runbook has Layer 2"
  assert_contains "$RUNBOOK" "pf" "Runbook covers pf"
  assert_contains "$RUNBOOK" "Layer 3" "Runbook has Layer 3"
  assert_contains "$RUNBOOK" "TLS" "Runbook covers TLS"
  assert_contains "$RUNBOOK" "Layer 4" "Runbook has Layer 4"
  assert_contains "$RUNBOOK" "X-Backend" "Runbook covers backend headers"
else
  fail "Runbook exists" "$RUNBOOK is missing"
fi

echo "=========================================================="
echo "Test Summary: $((TOTAL - FAILED)) / $TOTAL passed ($FAILED failed)"
echo "=========================================================="
[ "$FAILED" -eq 0 ]
