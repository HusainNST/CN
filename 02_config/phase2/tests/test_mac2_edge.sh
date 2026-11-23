#!/usr/bin/env bash
# ABOUTME: Test suite for the Mac 2 primary nginx Phase 2 IP refresh script (P2-02).
# ABOUTME: Checks input validation, upstream, failover and header lines, missing certificate refusal, and no key generation.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PHASE2_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$PHASE2_DIR/../.." && pwd)"
MAC2_EDGE="$PHASE2_DIR/mac2-edge-phase2.sh"

TMP_DIR="$(mktemp -d /tmp/cn_test_mac2_XXXXXX)"
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
  if bash "$MAC2_EDGE" --render-only "$out" "$@" >/dev/null 2>&1; then
    fail "$name" "script exited 0 for bad input: $*"
  elif [ -e "$out" ]; then
    fail "$name" "script wrote $out before rejecting bad input"
  else
    pass "$name"
  fi
}

echo "=========================================================="
echo "Running test suite: Mac 2 primary edge (P2-02)"
echo "=========================================================="

if [ ! -f "$MAC2_EDGE" ]; then
  fail "Script exists" "$MAC2_EDGE is missing"
  echo "Test Summary: $((TOTAL - FAILED)) / $TOTAL passed ($FAILED failed)"
  exit 1
fi

if bash -n "$MAC2_EDGE"; then pass "bash -n syntax check"; else fail "bash -n syntax check" "syntax error"; fi

PHASE1_SUMS_BEFORE="$(shasum "$REPO_ROOT/02_config/nginx-teamX.conf" "$REPO_ROOT/02_config/mac2-edge-setup.sh")"

echo "-- input validation"
assert_rejects "Rejects missing arguments"
assert_rejects "Rejects one argument" 10.7.18.190
assert_rejects "Rejects bad MAC3_IP" 10.7.18.300 10.7.24.166
assert_rejects "Rejects bad MAC4_IP" 10.7.18.190 mac4.local
assert_rejects "Rejects too many arguments" 10.7.18.190 10.7.24.166 10.7.22.227

echo "-- render"
CONF="$TMP_DIR/edge.conf"
if HOME="$TMP_DIR/home" bash "$MAC2_EDGE" --render-only "$CONF" 10.7.18.190 10.7.24.166 >/dev/null; then
  pass "Render exits 0 without certificates present"
else
  fail "Render exits 0 without certificates present" "non-zero exit"
fi
assert_contains "$CONF" "server 10.7.18.190:3001 max_fails=1 fail_timeout=10s;" "Upstream has Backend A with passive health check"
assert_contains "$CONF" "server 10.7.24.166:3002 max_fails=1 fail_timeout=10s;" "Upstream has Backend B with passive health check"
assert_contains "$CONF" "proxy_connect_timeout 2s;" "Connect timeout kept"
assert_contains "$CONF" "proxy_next_upstream error timeout http_502 http_503;" "Retry to next upstream kept"
assert_contains "$CONF" 'add_header X-Edge "mac2-nginx" always;' "X-Edge header kept"
assert_contains "$CONF" 'add_header X-Upstream-Addr $upstream_addr always;' "X-Upstream-Addr header kept"
assert_contains "$CONF" "http2 on;" "HTTP/2 kept"
assert_contains "$CONF" "ssl_protocols TLSv1.2 TLSv1.3;" "TLS versions kept"
assert_contains "$CONF" "ssl_certificate     $TMP_DIR/home/cn-project/tls/app.teamX.test.crt;" "Certificate path is under the user's cn-project/tls"
assert_contains "$CONF" "ssl_certificate_key $TMP_DIR/home/cn-project/tls/app.teamX.test.key;" "Key path is under the user's cn-project/tls"
assert_contains "$CONF" "return 301 https://\$host\$request_uri;" "HTTP to HTTPS redirect kept"

echo "-- live mode refuses to run without the existing certificate"
if HOME="$TMP_DIR/empty-home" bash "$MAC2_EDGE" 10.7.18.190 10.7.24.166 >"$TMP_DIR/live.out" 2>&1; then
  fail "Live mode fails when certificate is missing" "exited 0"
else
  assert_contains "$TMP_DIR/live.out" "app.teamX.test.crt" "Live mode names the missing certificate"
fi

echo "-- never generates keys or certificates"
if grep -Eq '(^|[^#])\bopenssl\b' "$MAC2_EDGE"; then
  fail "No openssl calls" "script calls openssl"
else
  pass "No openssl calls"
fi

echo "-- Phase 1 files untouched"
if [ "$PHASE1_SUMS_BEFORE" = "$(shasum "$REPO_ROOT/02_config/nginx-teamX.conf" "$REPO_ROOT/02_config/mac2-edge-setup.sh")" ]; then
  pass "nginx-teamX.conf and mac2-edge-setup.sh unchanged"
else
  fail "nginx-teamX.conf and mac2-edge-setup.sh unchanged" "checksum changed"
fi

echo "=========================================================="
echo "Test Summary: $((TOTAL - FAILED)) / $TOTAL passed ($FAILED failed)"
echo "=========================================================="
[ "$FAILED" -eq 0 ]
