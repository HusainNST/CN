# teamX 4-layer troubleshooting runbook (Phase 2, Extension F)

Work from Layer 1 upward. Stop at the first layer that fails, fix it, then
re-run every check from that layer up. Run commands from a client Mac unless
the line names a specific Mac. IPs come from `01_architecture/ip_table.md`.

## Layer 1: DNS (Mac 1 primary, Mac 3 backup)

| Check | Healthy result |
|---|---|
| `scutil --dns \| grep nameserver` | Mac 1 listed first, Mac 3 second |
| `dig @<MAC1_IP> app.teamX.test +noall +answer` | A record = current edge IP, TTL <= 30 |
| `dig @<MAC3_IP> app.teamX.test +noall +answer` | same answer as Mac 1 |
| `dig app.teamX.test +noall +answer` | system resolver agrees with the line above |

Common faults: dnsmasq down (`sudo brew services restart dnsmasq`), wrong
`host-record`, stale client cache (`sudo dscacheutil -flushcache; sudo killall
-HUP mDNSResponder`), or the client not using Mac 1/Mac 3 as resolvers.

## Layer 2: Network, TCP and pf

| Check | Healthy result |
|---|---|
| `ping -c 3 <EDGE_IP>` | 0% packet loss |
| `nc -vz <EDGE_IP> 443` | `succeeded` |
| `nc -vz <MAC3_IP> 3001` from a client | refused (pf blocks clients) |
| `nc -vz <MAC3_IP> 3001` from the edge | `succeeded` |
| `sudo pfctl -a teamX-backend -sr` on Mac 3/Mac 4 | pass lo0, pass edge IP(s), block return-rst |
| `sudo pfctl -s info \| head -1` | `Status: Enabled` while isolation is on |

Common faults: changed DHCP lease (update IPs, re-run scripts), edge IP missing
from the pf anchor (the standby edge must be listed too), backend not
listening (`lsof -nP -iTCP:3001 -sTCP:LISTEN`). Undo pf with
`pf-backend-rollback.sh`.

## Layer 3: TLS

| Check | Healthy result |
|---|---|
| `openssl s_client -connect app.teamX.test:443 -servername app.teamX.test </dev/null 2>/dev/null \| grep -E "subject=\|issuer=\|Verify return"` | issuer `teamX Local Root CA`, `Verify return code: 0 (ok)` |
| `openssl s_client -connect app.teamX.test:443 -servername app.teamX.test </dev/null 2>/dev/null \| openssl x509 -noout -text \| grep DNS:` | `DNS:app.teamX.test, DNS:api.teamX.test` |
| `curl -sv https://app.teamX.test/ -o /dev/null 2>&1 \| grep -E "SSL connection\|ALPN"` | TLSv1.3 or TLSv1.2, ALPN `h2` |

Common faults: client has not trusted `02_config/teamX-rootCA.crt`, cert
expired or missing a SAN, nginx pointing at the wrong cert/key pair, or
the standby cert was signed by some CA other than teamX-rootCA.

## Layer 4: HTTP, proxy and backends

| Check | Healthy result |
|---|---|
| `curl -s -D - -o /dev/null https://app.teamX.test/ \| grep -iE "^HTTP\|x-edge\|x-upstream"` | `200`, `X-Edge` names the active edge |
| `for i in 1 2 3 4; do curl -s https://app.teamX.test/ -D - -o /dev/null \| grep -i x-upstream; done` | alternates between Backend A and B |
| `sudo nginx -t` on the edge | `syntax is ok`, `test is successful` |
| `tail -n 20 $(brew --prefix)/var/log/nginx/teamX_access.log` on the edge | requests with an upstream address and status |

Common faults: `502`/`504` means no backend answered (go back to Layer 2 for
3001/3002), nginx not reloaded after a config change (`sudo nginx -s reload`),
or the wrong `X-Edge` value, which means DNS still points at the other edge
(go back to Layer 1 and wait out the 30 s TTL).

## Record every drill

Note the injected fault, the first failing check, the fix, and the passing
re-check. Save screenshots and output under `04_evidence/`.
