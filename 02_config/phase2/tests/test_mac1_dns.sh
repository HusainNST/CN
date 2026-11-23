#!/usr/bin/env bash
# ABOUTME: Test suite for the Mac 1 primary dnsmasq Phase 2 script (P2-01).
# ABOUTME: Checks input validation, the default TTL=30 render, and the app.teamX.test record switch render.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PHASE2_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$PHASE2_DIR/../.." && pwd)"
MAC1_DNS="$PHASE2_DIR/mac1-dns-phase2.sh"
PHASE1_CONF="$REPO_ROOT/02_config/dnsmasq-teamX.conf"

TMP_DIR="$(mktemp -d /tmp/cn_test_mac1_XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT

TOTAL=0
FAILED=0
pass() { TOTAL=$((TOTAL + 1)); echo "  [PASS] $1"; }
fail() { TOTAL=$((TOTAL + 1)); FAILED=$((FAILED + 1)); echo "  [FAIL] $1: $2" >&2; }

assert_contains() {
  if grep -Fxq "$2" "$1"; then pass "$3"; else fail "$3" "line '$2' not found in $1"; fi
}
assert_not_contains() {
  if ! grep -Fq "$2" "$1"; then pass "$3"; else fail "$3" "'$2' unexpectedly found in $1"; fi
}
assert_rejects() {
  local name="$1"; shift
  local out="$TMP_DIR/rejected.conf"
  rm -f "$out"
  if bash "$MAC1_DNS" --render-only "$out" "$@" >/dev/null 2>&1; then
    fail "$name" "script exited 0 for bad input: $*"
  elif [ -e "$out" ]; then
    fail "$name" "script wrote $out before rejecting bad input"
  else
    pass "$name"
  fi
}

echo "=========================================================="
echo "Running test suite: Mac 1 primary DNS (P2-01)"
echo "=========================================================="

if [ ! -f "$MAC1_DNS" ]; then
  fail "Script exists" "$MAC1_DNS is missing"
  echo "Test Summary: $((TOTAL - FAILED)) / $TOTAL passed ($FAILED failed)"
  exit 1
fi

if bash -n "$MAC1_DNS"; then pass "bash -n syntax check"; else fail "bash -n syntax check" "syntax error"; fi

PHASE1_SUM_BEFORE="$(shasum "$PHASE1_CONF" | cut -d' ' -f1)"

echo "-- input validation"
assert_rejects "Rejects missing arguments"
assert_rejects "Rejects one argument" 10.7.10.22
assert_rejects "Rejects bad MAC1_IP" 10.7.10.999 10.7.22.227
assert_rejects "Rejects non IPv4 edge IP" 10.7.10.22 app.teamX.test
assert_rejects "Rejects leading zero octet" 10.7.010.22 10.7.22.227
assert_rejects "Rejects zero TTL" 10.7.10.22 10.7.22.227 0
assert_rejects "Rejects text TTL" 10.7.10.22 10.7.22.227 thirty
assert_rejects "Rejects too many arguments" 10.7.10.22 10.7.22.227 30 extra

echo "-- default render (TTL=30, edge = Mac 2)"
CONF="$TMP_DIR/primary.conf"
if bash "$MAC1_DNS" --render-only "$CONF" 10.7.10.22 10.7.22.227 >/dev/null; then
  pass "Render exits 0"
else
  fail "Render exits 0" "non-zero exit"
fi
for line in \
  "listen-address=127.0.0.1,10.7.10.22" \
  "bind-interfaces" \
  "no-resolv" \
  "server=1.1.1.1" \
  "server=8.8.8.8" \
  "domain-needed" \
  "bogus-priv" \
  "local=/teamX.test/" \
  "host-record=app.teamX.test,10.7.22.227" \
  "host-record=api.teamX.test,10.7.22.227" \
  "local-ttl=30" \
  "log-queries"; do
  assert_contains "$CONF" "$line" "Default render has '$line'"
done

echo "-- record switch render (edge cutover to Mac 4, TTL 30)"
SWITCH="$TMP_DIR/switch.conf"
bash "$MAC1_DNS" --render-only "$SWITCH" 10.7.10.22 10.7.24.166 30 >/dev/null
assert_contains "$SWITCH" "host-record=app.teamX.test,10.7.24.166" "Switched app record points at new edge"
assert_contains "$SWITCH" "host-record=api.teamX.test,10.7.24.166" "Switched api record points at new edge"
assert_not_contains "$SWITCH" "10.7.22.227" "Switched render has no old edge IP"

echo "-- custom TTL"
CUSTOM="$TMP_DIR/custom.conf"
bash "$MAC1_DNS" --render-only "$CUSTOM" 10.7.10.22 10.7.22.227 60 >/dev/null
assert_contains "$CUSTOM" "local-ttl=60" "Custom TTL rendered"

echo "-- Phase 1 config untouched"
if [ "$PHASE1_SUM_BEFORE" = "$(shasum "$PHASE1_CONF" | cut -d' ' -f1)" ]; then
  pass "02_config/dnsmasq-teamX.conf unchanged"
else
  fail "02_config/dnsmasq-teamX.conf unchanged" "checksum changed"
fi

echo "=========================================================="
echo "Test Summary: $((TOTAL - FAILED)) / $TOTAL passed ($FAILED failed)"
echo "=========================================================="
[ "$FAILED" -eq 0 ]
