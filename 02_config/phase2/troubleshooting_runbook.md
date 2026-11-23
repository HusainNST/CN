# Troubleshooting runbook (Extension F)

Use this order when something is broken. Each layer depends on the one
before it, so a failure at a lower layer explains every symptom above it.
Say each check and its result out loud. The first layer that fails is where
the fault is.

Run checks from a client (Mac 1 or Mac 4) unless a step names another Mac.
Replace `<MAC2_IP>` and the other placeholders with values from
[ip_table.md](../../01_architecture/ip_table.md).

## Layer 1: DNS (does the name resolve to the right edge?)

| Check | Healthy result |
| --- | --- |
| `scutil --dns \| grep nameserver` | Mac 1 first, Mac 3 second |
| `dig app.teamX.test +noall +answer` | `app.teamX.test. <TTL> IN A <MAC2_IP>` |
| `dig @<MAC1_IP> app.teamX.test +short` | `<MAC2_IP>` (primary up) |
| `dig @<MAC3_IP> app.teamX.test +short` | `<MAC2_IP>` (backup agrees) |
| `dscacheutil -q host -a name app.teamX.test` | Same IP as `dig` (client cache not stale) |

Typical faults: dnsmasq stopped (`connection timed out; no servers could be
reached`), wrong record (answer is not the edge IP), Mac 1 and Mac 3 records
disagree, stale client cache (flush with
`sudo dscacheutil -flushcache && sudo killall -HUP mDNSResponder`).

## Layer 2: Network and TCP (can packets reach the port?)

| Check | Healthy result |
| --- | --- |
| `ping -c 3 <MAC2_IP>` | 0% packet loss |
| `nc -vz app.teamX.test 443` | `succeeded` |
| On Mac 2: `nc -vz <MAC3_IP> 3001` and `nc -vz <MAC4_IP> 3002` | Both `succeeded` |
| On Mac 3 and Mac 4: `sudo pfctl -a teamX-backend -sr` | Mac 2's IP in a `pass` rule |

Typical faults: wrong port, nginx not listening (`Connection refused`), pf
anchor missing the edge IP (Mac 2 gets RST from the backend), host down or
Wi-Fi changed (ping fails).

## Layer 3: TLS (does the client trust the edge?)

| Check | Healthy result |
| --- | --- |
| `curl -v https://app.teamX.test/api/status 2>&1 \| grep -E "SSL certificate verify\|subject:\|issuer:"` | `SSL certificate verify ok`, issuer `teamX Local Root CA` |
| `openssl s_client -connect app.teamX.test:443 -servername app.teamX.test </dev/null \| grep -E "Verify return\|subjectAltName"` | `Verify return code: 0 (ok)` |

Typical faults: expired or wrong certificate, hostname missing from SAN, client
does not trust the root CA, standby edge using a certificate signed by a
different CA. Never "fix" this with `curl -k`.

## Layer 4: HTTP, proxy, and backends (does the application answer?)

| Check | Healthy result |
| --- | --- |
| `for i in 1 2 3 4 5 6; do curl -sI https://app.teamX.test/api/status \| grep -Ei "^(HTTP\|x-backend\|x-edge)"; done` | `HTTP/2 200`, `X-Backend` alternates A and B, `X-Edge: mac2-nginx` |
| On Mac 2: `sudo nginx -t` | `syntax is ok` and `test is successful` |
| On Mac 2: `tail -n 20 $(brew --prefix)/var/log/nginx/teamX_access.log` | `upstream=` shows both backends with `(200)` |
| On Mac 3: `lsof -nP -iTCP:3001 -sTCP:LISTEN` / Mac 4: `-iTCP:3002` | `Python` listening |

Typical faults: one backend stopped (all responses from the other backend), both
stopped (`502 Bad Gateway`), wrong upstream IP or port in nginx, nginx config
error after an edit.

## After the fix

Re-run the failing check, then the full Layer 4 loop. Record the symptom,
the layer, the root cause, the fix, and the verification in
`04_evidence/P2_F_troubleshooting/drill_findings.md`.
