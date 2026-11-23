#!/usr/bin/env bash
# ABOUTME: Test suite for the Mac 1 primary dnsmasq Phase 2 script (mac1-dns-phase2.sh).
# ABOUTME: Verifies bad input rejection, default TTL=30 render, record-switch render, and Phase 1 config untouched.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PHASE2_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$PHASE2_DIR/../.." && pwd)"

MAC1_DNS="$PHASE2_DIR/mac1-dns-phase2.sh"
PHASE1_CONF="$REPO_ROOT/02_config/dnsmasq-teamX.conf"

MAC1_IP="10.7.4.108"
PRIMARY_EDGE="10.7.6.184"
STANDBY_EDGE="10.7.3.254"

TMP_DIR="$(mktemp -d /tmp/cn_test_mac1_XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT

TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

pass() {
  TOTAL_TESTS=$((TOTAL_TESTS + 1))
  PASSED_TESTS=$((PASSED_TESTS + 1))
  echo "  [PASS] $1"
}

fail() {
  TOTAL_TESTS=$((TOTAL_TESTS + 1))
  FAILED_TESTS=$((FAILED_TESTS + 1))
  echo "  [FAIL] $1: $2" >&2
}

assert_file_contains() {
  local file="$1"
  local pattern="$2"
  local test_name="$3"
  if grep -Fxq "$pattern" "$file"; then
    pass "$test_name"
  else
    fail "$test_name" "Line '$pattern' not found in $file"
  fi
}

assert_file_not_contains() {
  local file="$1"
  local pattern="$2"
  local test_name="$3"
  if ! grep -Fq "$pattern" "$file"; then
    pass "$test_name"
  else
    fail "$test_name" "Pattern '$pattern' unexpectedly found in $file"
  fi
}

assert_rejects() {
  local test_name="$1"
  shift
  if ! bash "$MAC1_DNS" "$@" >/dev/null 2>&1; then
    pass "$test_name"
  else
    fail "$test_name" "Did not exit non-zero for: $*"
  fi
}

PHASE1_HASH_BEFORE="$(shasum -a 256 "$PHASE1_CONF" | awk '{print $1}')"

echo "=========================================================="
echo "Running test suite: Mac 1 Primary DNS Phase 2 Script"
echo "=========================================================="

# ------------------------------------------------------------
# 1. bash -n Syntax Validation
# ------------------------------------------------------------
echo "1. Checking bash -n syntax..."
if bash -n "$MAC1_DNS"; then
  pass "bash -n mac1-dns-phase2.sh syntax ok"
else
  fail "bash -n mac1-dns-phase2.sh" "Script contains syntax errors"
fi

# ------------------------------------------------------------
# 2. Bad Input Rejection
# ------------------------------------------------------------
echo "2. Testing bad input rejection..."
OUT="$TMP_DIR/should_not_exist.conf"
assert_rejects "Rejects missing arguments"
assert_rejects "Rejects a single argument" "$MAC1_IP"
assert_rejects "Rejects too many arguments" --render-only "$OUT" "$MAC1_IP" "$PRIMARY_EDGE" 30 extra
assert_rejects "Rejects --render-only without a path" --render-only
assert_rejects "Rejects invalid MAC1_IP (999.1.1.1)" --render-only "$OUT" 999.1.1.1 "$PRIMARY_EDGE"
assert_rejects "Rejects invalid TARGET_EDGE_IP (256.0.0.1)" --render-only "$OUT" "$MAC1_IP" 256.0.0.1
assert_rejects "Rejects 3-octet IP (10.7.4)" --render-only "$OUT" 10.7.4 "$PRIMARY_EDGE"
assert_rejects "Rejects leading-zero octet (10.07.4.108)" --render-only "$OUT" 10.07.4.108 "$PRIMARY_EDGE"
assert_rejects "Rejects hostname instead of IP" --render-only "$OUT" "$MAC1_IP" app.teamX.test
assert_rejects "Rejects TTL=0" --render-only "$OUT" "$MAC1_IP" "$PRIMARY_EDGE" 0
assert_rejects "Rejects non-numeric TTL" --render-only "$OUT" "$MAC1_IP" "$PRIMARY_EDGE" abc
assert_rejects "Rejects negative TTL" --render-only "$OUT" "$MAC1_IP" "$PRIMARY_EDGE" -5
if [ ! -e "$OUT" ]; then
  pass "No output file written on bad input"
else
  fail "No output on bad input" "$OUT was created"
fi

# ------------------------------------------------------------
# 3. Default TTL=30 Render
# ------------------------------------------------------------
echo "3. Testing default render (TTL=30)..."
CONF_DEFAULT="$TMP_DIR/primary_default.conf"
if bash "$MAC1_DNS" --render-only "$CONF_DEFAULT" "$MAC1_IP" "$PRIMARY_EDGE" >/dev/null; then
  pass "Renders with default TTL"
  assert_file_contains "$CONF_DEFAULT" "listen-address=127.0.0.1,$MAC1_IP" "listen-address set"
  assert_file_contains "$CONF_DEFAULT" "bind-interfaces" "bind-interfaces set"
  assert_file_contains "$CONF_DEFAULT" "no-resolv" "no-resolv set"
  assert_file_contains "$CONF_DEFAULT" "server=1.1.1.1" "upstream 1.1.1.1 set"
  assert_file_contains "$CONF_DEFAULT" "server=8.8.8.8" "upstream 8.8.8.8 set"
  assert_file_contains "$CONF_DEFAULT" "domain-needed" "domain-needed set"
  assert_file_contains "$CONF_DEFAULT" "bogus-priv" "bogus-priv set"
  assert_file_contains "$CONF_DEFAULT" "local=/teamX.test/" "local=/teamX.test/ set"
  assert_file_contains "$CONF_DEFAULT" "host-record=app.teamX.test,$PRIMARY_EDGE" "app.teamX.test -> primary edge"
  assert_file_contains "$CONF_DEFAULT" "host-record=api.teamX.test,$PRIMARY_EDGE" "api.teamX.test -> primary edge"
  assert_file_contains "$CONF_DEFAULT" "local-ttl=30" "default local-ttl=30 set"
  assert_file_contains "$CONF_DEFAULT" "log-queries" "log-queries enabled"
  TTL_LINES="$(grep -c '^local-ttl=' "$CONF_DEFAULT" || true)"
  if [ "$TTL_LINES" -eq 1 ]; then
    pass "Exactly one local-ttl line"
  else
    fail "local-ttl line count" "Expected 1, got $TTL_LINES"
  fi
else
  fail "Default render" "Script exited non-zero"
fi

CONF_CUSTOM="$TMP_DIR/primary_custom.conf"
if bash "$MAC1_DNS" --render-only "$CONF_CUSTOM" "$MAC1_IP" "$PRIMARY_EDGE" 120 >/dev/null; then
  pass "Renders with custom TTL=120"
  assert_file_contains "$CONF_CUSTOM" "local-ttl=120" "custom local-ttl=120 set"
else
  fail "Custom TTL render" "Script exited non-zero"
fi

# ------------------------------------------------------------
# 4. Record Switch Render (primary edge -> standby edge)
# ------------------------------------------------------------
echo "4. Testing record switch render..."
CONF_SWITCH="$TMP_DIR/primary_switch.conf"
cp "$CONF_DEFAULT" "$CONF_SWITCH"
if bash "$MAC1_DNS" --render-only "$CONF_SWITCH" "$MAC1_IP" "$STANDBY_EDGE" >/dev/null; then
  pass "Re-render to the same path with standby edge succeeds"
  assert_file_contains "$CONF_SWITCH" "host-record=app.teamX.test,$STANDBY_EDGE" "app.teamX.test -> standby edge"
  assert_file_contains "$CONF_SWITCH" "host-record=api.teamX.test,$STANDBY_EDGE" "api.teamX.test -> standby edge"
  assert_file_not_contains "$CONF_SWITCH" "$PRIMARY_EDGE" "Old edge IP fully removed after switch"
  assert_file_contains "$CONF_SWITCH" "local-ttl=30" "TTL unchanged across switch"
  RECORD_LINES="$(grep -c '^host-record=' "$CONF_SWITCH" || true)"
  if [ "$RECORD_LINES" -eq 2 ]; then
    pass "Exactly two host-record lines after switch"
  else
    fail "host-record line count" "Expected 2, got $RECORD_LINES"
  fi
  if diff <(grep -v '^host-record=' "$CONF_DEFAULT") <(grep -v '^host-record=' "$CONF_SWITCH") >/dev/null; then
    pass "Only host-record lines differ between primary and standby renders"
  else
    fail "Switch diff scope" "Lines other than host-record changed"
  fi
else
  fail "Record switch render" "Script exited non-zero"
fi

# ------------------------------------------------------------
# 5. dnsmasq --test on the rendered config (if dnsmasq is installed)
# ------------------------------------------------------------
echo "5. Validating rendered config with dnsmasq --test (if available)..."
DNSMASQ_BIN=""
for candidate in /opt/homebrew/sbin/dnsmasq /usr/local/sbin/dnsmasq; do
  if [ -x "$candidate" ]; then
    DNSMASQ_BIN="$candidate"
    break
  fi
done
if [ -n "$DNSMASQ_BIN" ]; then
  if "$DNSMASQ_BIN" --test --conf-file="$CONF_DEFAULT" >/dev/null 2>&1; then
    pass "dnsmasq --test accepts the default render"
  else
    fail "dnsmasq --test" "dnsmasq rejected the rendered config"
  fi
else
  echo "  [SKIP] dnsmasq not installed; syntax check skipped"
fi

# ------------------------------------------------------------
# 6. Phase 1 config untouched
# ------------------------------------------------------------
echo "6. Checking Phase 1 dnsmasq-teamX.conf is untouched..."
PHASE1_HASH_AFTER="$(shasum -a 256 "$PHASE1_CONF" | awk '{print $1}')"
if [ "$PHASE1_HASH_BEFORE" = "$PHASE1_HASH_AFTER" ]; then
  pass "02_config/dnsmasq-teamX.conf unchanged by test runs"
else
  fail "Phase 1 config" "02_config/dnsmasq-teamX.conf changed during tests"
fi
if ! grep -q 'dnsmasq-teamX.conf' <(grep -v '^#' "$MAC1_DNS"); then
  pass "Script does not reference the Phase 1 config file"
else
  fail "Phase 1 reference" "mac1-dns-phase2.sh references dnsmasq-teamX.conf outside comments"
fi

echo "=========================================================="
echo "Test Summary: $PASSED_TESTS / $TOTAL_TESTS passed ($FAILED_TESTS failed)"
echo "=========================================================="

if [ "$FAILED_TESTS" -eq 0 ]; then
  echo "All tests passed successfully!"
  exit 0
else
  echo "Some tests failed." >&2
  exit 1
fi
