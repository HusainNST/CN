#!/usr/bin/env bash
# ABOUTME: Translates the teamX-backend pf anchor rendered by pf-backend-isolate.sh into equivalent iptables rules.
# ABOUTME: Lets the Linux containers enforce the same allow and block list that macOS pf enforces on the real Macs.
set -euo pipefail

ANCHOR="${1:?usage: pf-anchor-to-iptables <anchor_file>}"
CHAIN=TEAMX-BACKEND

iptables -N "$CHAIN" 2>/dev/null || iptables -F "$CHAIN"
iptables -C INPUT -j "$CHAIN" 2>/dev/null || iptables -I INPUT 1 -j "$CHAIN"

while IFS= read -r line; do
  case "$line" in
    ''|'#'*) continue ;;
  esac
  port="$(sed -nE 's/.* port ([0-9]+)$/\1/p' <<<"$line")"
  if [[ "$line" =~ ^pass\ in\ quick\ on\ lo0 ]]; then
    rule=(-i lo -p tcp --dport "$port" -j ACCEPT)                       # pf: on lo0
  elif [[ "$line" =~ ^pass\ in\ quick\ on\ en0\ proto\ tcp\ from\ ([0-9.]+) ]]; then
    rule=(! -i lo -s "${BASH_REMATCH[1]}" -p tcp --dport "$port" -j ACCEPT)   # pf: on en0 from IP
  elif [[ "$line" =~ ^block\ return-rst\ in\ quick\ on\ en0 ]]; then
    rule=(! -i lo -p tcp --dport "$port" -j REJECT --reject-with tcp-reset)   # pf: return-rst
  else
    echo "Unrecognised pf rule: $line" >&2
    exit 1
  fi
  iptables -A "$CHAIN" "${rule[@]}"
done < "$ANCHOR"

echo "iptables equivalent now loaded ($CHAIN):"
iptables -S "$CHAIN" | sed 's/^/  /'
