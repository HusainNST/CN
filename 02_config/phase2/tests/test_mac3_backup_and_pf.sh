#!/usr/bin/env bash
# ABOUTME: Unit and regression test suite for Mac 3 backup dnsmasq and shared backend pf isolation scripts.
# ABOUTME: Verifies backup DNS render, pf anchor rules (1 & 2 edge IPs), idempotent pf.conf insertion, input validation, and rollback restore.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PHASE2_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

MAC3_DNS="$PHASE2_DIR/mac3-backup-dns.sh"
PF_ISOLATE="$PHASE2_DIR/pf-backend-isolate.sh"
PF_ROLLBACK="$PHASE2_DIR/pf-backend-rollback.sh"

TMP_DIR="$(mktemp -d /tmp/cn_test_mac3_XXXXXX)"
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
  if grep -Fq "$pattern" "$file"; then
    pass "$test_name"
  else
    fail "$test_name" "Pattern '$pattern' not found in $file"
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

echo "=========================================================="
echo "Running test suite: Mac 3 Backup DNS and PF Scripts"
echo "=========================================================="

# ------------------------------------------------------------
# 1. bash -n Syntax Validation
# ------------------------------------------------------------
echo "1. Checking bash -n syntax on all scripts..."
for script in "$MAC3_DNS" "$PF_ISOLATE" "$PF_ROLLBACK"; do
  name="$(basename "$script")"
  if bash -n "$script"; then
    pass "bash -n $name syntax ok"
  else
    fail "bash -n $name syntax error" "Script contains syntax errors"
  fi
done

# ------------------------------------------------------------
# 2. Backup DNS Render Tests (mac3-backup-dns.sh)
# ------------------------------------------------------------
echo "2. Testing backup dnsmasq rendering..."
DNS_CONF_DEFAULT="$TMP_DIR/dnsmasq_default.conf"
if bash "$MAC3_DNS" --render-only "$DNS_CONF_DEFAULT" 10.7.18.190 10.7.22.227 >/dev/null; then
  pass "mac3-backup-dns.sh renders with default TTL=30"
  assert_file_contains "$DNS_CONF_DEFAULT" "listen-address=127.0.0.1,10.7.18.190" "DNS listen-address set"
  assert_file_contains "$DNS_CONF_DEFAULT" "bind-interfaces" "DNS bind-interfaces set"
  assert_file_contains "$DNS_CONF_DEFAULT" "no-resolv" "DNS no-resolv set"
  assert_file_contains "$DNS_CONF_DEFAULT" "server=1.1.1.1" "DNS upstream 1.1.1.1 set"
  assert_file_contains "$DNS_CONF_DEFAULT" "server=8.8.8.8" "DNS upstream 8.8.8.8 set"
  assert_file_contains "$DNS_CONF_DEFAULT" "domain-needed" "DNS domain-needed set"
  assert_file_contains "$DNS_CONF_DEFAULT" "bogus-priv" "DNS bogus-priv set"
  assert_file_contains "$DNS_CONF_DEFAULT" "local=/teamX.test/" "DNS local authoritative domain set"
  assert_file_contains "$DNS_CONF_DEFAULT" "host-record=app.teamX.test,10.7.22.227" "DNS app.teamX.test record set"
  assert_file_contains "$DNS_CONF_DEFAULT" "host-record=api.teamX.test,10.7.22.227" "DNS api.teamX.test record set"
  assert_file_contains "$DNS_CONF_DEFAULT" "local-ttl=30" "DNS default local-ttl=30 set"
  assert_file_contains "$DNS_CONF_DEFAULT" "log-queries" "DNS log-queries enabled"
else
  fail "mac3-backup-dns.sh default render" "Script exited non-zero"
fi

DNS_CONF_CUSTOM="$TMP_DIR/dnsmasq_custom.conf"
if bash "$MAC3_DNS" --render-only "$DNS_CONF_CUSTOM" 10.7.18.190 10.7.22.227 45 >/dev/null; then
  pass "mac3-backup-dns.sh renders with custom TTL=45"
  assert_file_contains "$DNS_CONF_CUSTOM" "local-ttl=45" "DNS custom local-ttl=45 set"
else
  fail "mac3-backup-dns.sh custom render" "Script exited non-zero"
fi

# ------------------------------------------------------------
# 3. Bad Port / IP Rejection Tests
# ------------------------------------------------------------
echo "3. Testing bad port and IP input rejection..."

# DNS bad inputs
if ! bash "$MAC3_DNS" >/dev/null 2>&1; then
  pass "mac3-backup-dns.sh rejects missing arguments"
else
  fail "mac3-backup-dns.sh missing arguments" "Did not exit non-zero"
fi

if ! bash "$MAC3_DNS" --render-only "$TMP_DIR/out" 999.1.1.1 10.7.22.227 >/dev/null 2>&1; then
  pass "mac3-backup-dns.sh rejects invalid MAC3_IP (999.1.1.1)"
else
  fail "mac3-backup-dns.sh invalid MAC3_IP" "Did not reject 999.1.1.1"
fi

if ! bash "$MAC3_DNS" --render-only "$TMP_DIR/out" 10.7.18.190 256.0.0.1 >/dev/null 2>&1; then
  pass "mac3-backup-dns.sh rejects invalid TARGET_EDGE_IP (256.0.0.1)"
else
  fail "mac3-backup-dns.sh invalid TARGET_EDGE_IP" "Did not reject 256.0.0.1"
fi

if ! bash "$MAC3_DNS" --render-only "$TMP_DIR/out" 10.7.18.190 10.7.22.227 0 >/dev/null 2>&1; then
  pass "mac3-backup-dns.sh rejects invalid TTL=0"
else
  fail "mac3-backup-dns.sh invalid TTL=0" "Did not reject TTL=0"
fi

if ! bash "$MAC3_DNS" --render-only "$TMP_DIR/out" 10.7.18.190 10.7.22.227 abc >/dev/null 2>&1; then
  pass "mac3-backup-dns.sh rejects non-numeric TTL"
else
  fail "mac3-backup-dns.sh non-numeric TTL" "Did not reject TTL=abc"
fi

# PF isolate bad inputs
if ! bash "$PF_ISOLATE" >/dev/null 2>&1; then
  pass "pf-backend-isolate.sh rejects missing arguments"
else
  fail "pf-backend-isolate.sh missing arguments" "Did not exit non-zero"
fi

if ! bash "$PF_ISOLATE" --render-only "$TMP_DIR/a" "$TMP_DIR/p" 0 10.7.22.227 >/dev/null 2>&1; then
  pass "pf-backend-isolate.sh rejects invalid port 0"
else
  fail "pf-backend-isolate.sh invalid port 0" "Did not reject port 0"
fi

if ! bash "$PF_ISOLATE" --render-only "$TMP_DIR/a" "$TMP_DIR/p" 65536 10.7.22.227 >/dev/null 2>&1; then
  pass "pf-backend-isolate.sh rejects invalid port 65536"
else
  fail "pf-backend-isolate.sh invalid port 65536" "Did not reject port 65536"
fi

if ! bash "$PF_ISOLATE" --render-only "$TMP_DIR/a" "$TMP_DIR/p" notaport 10.7.22.227 >/dev/null 2>&1; then
  pass "pf-backend-isolate.sh rejects non-numeric port"
else
  fail "pf-backend-isolate.sh non-numeric port" "Did not reject port notaport"
fi

if ! bash "$PF_ISOLATE" --render-only "$TMP_DIR/a" "$TMP_DIR/p" 3001 999.0.0.1 >/dev/null 2>&1; then
  pass "pf-backend-isolate.sh rejects invalid PRIMARY_EDGE_IP (999.0.0.1)"
else
  fail "pf-backend-isolate.sh invalid PRIMARY_EDGE_IP" "Did not reject 999.0.0.1"
fi

if ! bash "$PF_ISOLATE" --render-only "$TMP_DIR/a" "$TMP_DIR/p" 3001 10.7.22.227 10.7.22.300 >/dev/null 2>&1; then
  pass "pf-backend-isolate.sh rejects invalid STANDBY_EDGE_IP (10.7.22.300)"
else
  fail "pf-backend-isolate.sh invalid STANDBY_EDGE_IP" "Did not reject 10.7.22.300"
fi

# ------------------------------------------------------------
# 4. PF Anchor Rules with 1 and 2 Edge IPs
# ------------------------------------------------------------
echo "4. Testing PF anchor rule rendering (1 and 2 edge IPs)..."

# 1 Edge IP test (Mac 3 port 3001)
ANCHOR_1="$TMP_DIR/anchor_1edge.conf"
PFCONF_1="$TMP_DIR/pf_1edge.conf"
if bash "$PF_ISOLATE" --render-only "$ANCHOR_1" "$PFCONF_1" 3001 10.7.22.227 >/dev/null; then
  pass "pf-backend-isolate.sh renders 1-edge rule successfully"
  assert_file_contains "$ANCHOR_1" "pass in quick on lo0 proto tcp to any port 3001" "Anchor lo0 pass rule present"
  assert_file_contains "$ANCHOR_1" "pass in quick proto tcp from 10.7.22.227 to any port 3001" "Anchor primary edge pass rule present"
  assert_file_contains "$ANCHOR_1" "block return-rst in quick proto tcp to any port 3001" "Anchor block return-rst rule present"

  # Ensure count of edge pass rules is exactly 1
  EDGE_PASS_COUNT="$(grep -c "pass in quick proto tcp from" "$ANCHOR_1" || true)"
  if [ "$EDGE_PASS_COUNT" -eq 1 ]; then
    pass "Single edge IP produces exactly 1 edge pass rule"
  else
    fail "Single edge IP pass count" "Expected 1 rule, got $EDGE_PASS_COUNT"
  fi
  if awk '/^pass / { pass_line = NR } /^block return-rst / { block_line = NR } END { exit !(pass_line < block_line) }' "$ANCHOR_1"; then
    pass "Pass rules precede block return-rst rule"
  else
    fail "PF rule order" "A pass rule must precede block return-rst"
  fi

  if command -v pfctl >/dev/null 2>&1; then
    if pfctl -nf "$ANCHOR_1" >/dev/null 2>&1; then
      pass "pfctl -nf validates 1-edge anchor rule syntax"
    else
      fail "pfctl -nf 1-edge" "pfctl syntax validation failed"
    fi
  fi
else
  fail "pf-backend-isolate.sh 1-edge render" "Script exited non-zero"
fi

# 2 Edge IPs test (Mac 4 port 3002 with primary & standby edge)
ANCHOR_2="$TMP_DIR/anchor_2edge.conf"
PFCONF_2="$TMP_DIR/pf_2edge.conf"
if bash "$PF_ISOLATE" --render-only "$ANCHOR_2" "$PFCONF_2" 3002 10.7.22.227 10.7.24.166 >/dev/null; then
  pass "pf-backend-isolate.sh renders 2-edge rule successfully"
  assert_file_contains "$ANCHOR_2" "pass in quick on lo0 proto tcp to any port 3002" "Anchor lo0 pass rule present (3002)"
  assert_file_contains "$ANCHOR_2" "pass in quick proto tcp from 10.7.22.227 to any port 3002" "Anchor primary edge pass rule present (3002)"
  assert_file_contains "$ANCHOR_2" "pass in quick proto tcp from 10.7.24.166 to any port 3002" "Anchor standby edge pass rule present (3002)"
  assert_file_contains "$ANCHOR_2" "block return-rst in quick proto tcp to any port 3002" "Anchor block return-rst rule present (3002)"

  EDGE_PASS_COUNT="$(grep -c "pass in quick proto tcp from" "$ANCHOR_2" || true)"
  if [ "$EDGE_PASS_COUNT" -eq 2 ]; then
    pass "Two edge IPs produce exactly 2 edge pass rules"
  else
    fail "Two edge IPs pass count" "Expected 2 rules, got $EDGE_PASS_COUNT"
  fi

  if command -v pfctl >/dev/null 2>&1; then
    if pfctl -nf "$ANCHOR_2" >/dev/null 2>&1; then
      pass "pfctl -nf validates 2-edge anchor rule syntax"
    else
      fail "pfctl -nf 2-edge" "pfctl syntax validation failed"
    fi
  fi
else
  fail "pf-backend-isolate.sh 2-edge render" "Script exited non-zero"
fi

# ------------------------------------------------------------
# 5. Idempotent /etc/pf.conf Anchor Insertion Test
# ------------------------------------------------------------
echo "5. Testing idempotent /etc/pf.conf anchor insertion..."
MOCK_PFCONF="$TMP_DIR/mock_etc_pf.conf"
cat <<'EOF' > "$MOCK_PFCONF"
# Default PF configuration file
scrub-anchor "com.apple/*"
nat-anchor "com.apple/*"
rdr-anchor "com.apple/*"
anchor "com.apple/*"
load anchor "com.apple" from "/etc/pf.anchors/com.apple"
EOF

# First insertion
bash "$PF_ISOLATE" --render-only "$TMP_DIR/a1.conf" "$MOCK_PFCONF" 3001 10.7.22.227 >/dev/null
COUNT1="$(grep -Ec '^[[:space:]]*anchor "teamX-backend"[[:space:]]*$' "$MOCK_PFCONF" || true)"
if [ "$COUNT1" -eq 1 ]; then
  pass "First run inserts anchor \"teamX-backend\" into mock pf.conf"
else
  fail "First insertion count" "Expected 1 occurrence, got $COUNT1"
fi

# Second insertion (idempotency check)
bash "$PF_ISOLATE" --render-only "$TMP_DIR/a2.conf" "$MOCK_PFCONF" 3001 10.7.22.227 >/dev/null
COUNT2="$(grep -Ec '^[[:space:]]*anchor "teamX-backend"[[:space:]]*$' "$MOCK_PFCONF" || true)"
if [ "$COUNT2" -eq 1 ]; then
  pass "Second run does NOT duplicate anchor \"teamX-backend\" (idempotent)"
else
  fail "Second insertion count" "Expected 1 occurrence, got $COUNT2"
fi

if command -v pfctl >/dev/null 2>&1; then
  if pfctl -nf "$MOCK_PFCONF" >/dev/null 2>&1; then
    pass "pfctl -nf validates mock pf.conf syntax with teamX-backend anchor"
  else
    fail "pfctl -nf pf.conf" "pfctl syntax validation failed on pf.conf"
  fi
fi

# ------------------------------------------------------------
# 6. Rollback Restore Tests (pf-backend-rollback.sh)
# ------------------------------------------------------------
echo "6. Testing rollback restore..."

# Missing arguments rejection
if ! bash "$PF_ROLLBACK" --dry-run >/dev/null 2>&1; then
  pass "pf-backend-rollback.sh rejects --dry-run with missing arguments"
else
  fail "pf-backend-rollback.sh --dry-run validation" "Did not exit non-zero"
fi

if ! bash "$PF_ROLLBACK" --help >/dev/null 2>&1; then
  pass "pf-backend-rollback.sh rejects unknown arguments"
else
  fail "pf-backend-rollback.sh unknown arguments" "Did not exit non-zero"
fi

# Nonexistent backup file rejection
if ! bash "$PF_ROLLBACK" --dry-run "$TMP_DIR/target" "$TMP_DIR/nonexistent_bak" >/dev/null 2>&1; then
  pass "pf-backend-rollback.sh rejects nonexistent backup file"
else
  fail "pf-backend-rollback.sh nonexistent backup" "Did not exit non-zero"
fi

# Dry run restore check
MOCK_BAK="$TMP_DIR/mock_pf.conf.phase1.bak"
cat <<'EOF' > "$MOCK_BAK"
# Untouched Phase 1 pf.conf
anchor "com.apple/*"
load anchor "com.apple" from "/etc/pf.anchors/com.apple"
EOF

MOCK_TARGET="$TMP_DIR/mock_live_pf.conf"
cat <<'EOF' > "$MOCK_TARGET"
# Untouched Phase 1 pf.conf
anchor "com.apple/*"
load anchor "com.apple" from "/etc/pf.anchors/com.apple"
anchor "teamX-backend"
EOF

if bash "$PF_ROLLBACK" --dry-run "$MOCK_TARGET" "$MOCK_BAK" >/dev/null; then
  pass "pf-backend-rollback.sh dry-run executes successfully"
  if diff -u "$MOCK_TARGET" "$MOCK_BAK" >/dev/null; then
    pass "pf-backend-rollback.sh restores pf.conf exactly to Phase 1 backup"
    assert_file_not_contains "$MOCK_TARGET" "anchor \"teamX-backend\"" "Anchor teamX-backend removed on rollback"
  else
    fail "Rollback file comparison" "Restored file differs from backup"
  fi
else
  fail "pf-backend-rollback.sh dry-run execution" "Script exited non-zero"
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
