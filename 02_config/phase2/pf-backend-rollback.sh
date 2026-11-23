#!/usr/bin/env bash
# ABOUTME: Shared backend pf rollback script for CN Project Phase 2 (Extension C).
# ABOUTME: Flushes teamX-backend anchor, restores /etc/pf.conf from Phase 1 backup, and restores pf state.
#
# Usage: ./pf-backend-rollback.sh [--dry-run <MOCK_PFCONF> <MOCK_BAK>]
#   e.g. sudo ./pf-backend-rollback.sh
#   e.g. ./pf-backend-rollback.sh --dry-run /tmp/mock_pf.conf /tmp/mock_pf.conf.phase1.bak
set -euo pipefail

DRY_RUN=0
MOCK_PFCONF=""
MOCK_BAK=""

if [ "${1:-}" = "--dry-run" ]; then
  if [ $# -ne 3 ]; then
    echo "Error: --dry-run requires <MOCK_PFCONF> and <MOCK_BAK> file paths." >&2
    echo "Usage: $0 [--dry-run <MOCK_PFCONF> <MOCK_BAK>]" >&2
    exit 1
  fi
  DRY_RUN=1
  MOCK_PFCONF="$2"
  MOCK_BAK="$3"
fi
if [ "$DRY_RUN" -eq 0 ] && [ "$#" -ne 0 ]; then
  echo "Error: Unknown arguments. Usage: $0 [--dry-run <MOCK_PFCONF> <MOCK_BAK>]" >&2
  exit 1
fi

if [ "$DRY_RUN" -eq 1 ]; then
  if [ ! -f "$MOCK_BAK" ]; then
    echo "Error: Mock backup file '$MOCK_BAK' does not exist." >&2
    exit 1
  fi
  echo "[dry-run] Flushing anchor teamX-backend..."
  echo "[dry-run] Restoring $MOCK_PFCONF from $MOCK_BAK..."
  cp "$MOCK_BAK" "$MOCK_PFCONF"
  echo "[dry-run] Reloading pfctl configuration from $MOCK_PFCONF..."
  echo "[dry-run] Restoring pf enabled/disabled state..."
  echo "[dry-run] Rollback complete."
  exit 0
fi

# Live mode requires root privileges
if [ "${EUID:-$(id -u)}" -ne 0 ]; then
  echo "Error: Live mode must be run with sudo (or as root)." >&2
  exit 1
fi

TARGET_HOME="${HOME}"
if [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ]; then
  USER_HOME="$(eval echo "~$SUDO_USER")"
  if [ -d "$USER_HOME" ]; then
    TARGET_HOME="$USER_HOME"
  fi
fi

BACKUP_DIR="$TARGET_HOME/cn-project"
PF_BAK="$BACKUP_DIR/pf.conf.phase1.bak"
PF_STATE="$BACKUP_DIR/pf.state.phase1"

# Stop before changing anything if the Phase 1 backup is missing; otherwise
# /etc/pf.conf would keep a load anchor line pointing at a deleted file.
if [ ! -f "$PF_BAK" ]; then
  echo "Error: Backup $PF_BAK not found. Nothing was changed." >&2
  echo "Restore /etc/pf.conf manually before removing /etc/pf.anchors/teamX-backend." >&2
  exit 1
fi

# 1. Flush teamX-backend anchor rules
echo "Flushing rules from anchor teamX-backend..."
pfctl -a teamX-backend -F rules 2>/dev/null || true
rm -f /etc/pf.anchors/teamX-backend

# 2. Restore /etc/pf.conf from backup
cp "$PF_BAK" /etc/pf.conf
echo "Restored /etc/pf.conf from $PF_BAK"

# 3. Reload pfctl
echo "Reloading /etc/pf.conf..."
pfctl -f /etc/pf.conf

# 4. Disable pf if originally disabled
if [ -f "$PF_STATE" ]; then
  ORIGINAL_STATE="$(tr -d '[:space:]' < "$PF_STATE")"
  if [ "$ORIGINAL_STATE" = "disabled" ]; then
    echo "Disabling pf (restoring original disabled state)..."
    pfctl -d 2>/dev/null || true
  else
    echo "Leaving pf enabled (restoring original enabled state)..."
  fi
else
  echo "Notice: Original state file $PF_STATE not found; pf enabled state left unchanged."
fi

echo ""
echo "==== PF Rollback Complete ===="
echo "Active rules in anchor teamX-backend (should be empty):"
pfctl -a teamX-backend -sr 2>/dev/null || true
