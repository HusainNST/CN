# Extension F: troubleshooting drill findings

Two blind drills on 23 Nov 2026. Each fault was injected by another Mac's
owner, who didn't say what it was. Mac 4 (`10.7.3.254`) diagnosed both as a
client with `02_config/phase2/troubleshooting_runbook.md`, going DNS, then TCP,
then TLS, then HTTP, and stopping at the first layer that failed. The injector
confirmed what they did only after the diagnosis was posted on #17.

For the drills, Mac 4's Wi-Fi DNS was set to `10.7.4.108 10.7.30.194` (Mac 1
first, Mac 3 second). Baseline at 16:56 IST: `app.teamX.test` resolved to
`10.7.6.184` with TTL 30, and HTTPS returned `HTTP/2 200` through `mac2-nginx`.

## Drill 1: DNS layer (injected on Mac 1)

**Symptom.** At 17:03:51 IST, `curl https://app.teamX.test/api/status` failed
with `Failed to connect to app.teamX.test port 443`.

**Diagnosis** (`P2F-01_drill1_diagnosis.png`):

| Layer | Check | Result |
|---|---|---|
| 1 DNS | `scutil --dns` | Mac 1 first, Mac 3 second, as configured |
| 1 DNS | `dig @10.7.4.108 app.teamX.test` | `A 10.7.30.194`, wrong |
| 1 DNS | `dig @10.7.30.194 app.teamX.test` | `A 10.7.6.184`, right |
| 1 DNS | `dscacheutil -q host -a name app.teamX.test` | `10.7.30.194` cached |
| 2 TCP | `nc -vz 10.7.30.194 443` | `Connection refused`, because Mac 3 runs no edge |
| 2–4 | `curl --resolve app.teamX.test:443:10.7.6.184 ...` | `HTTP/2 200`, `mac2-nginx`, so the edge is fine |

Layer 1 fails. The two resolvers disagree, and Mac 4 never falls back to Mac 3
because Mac 1 keeps answering, just with the wrong IP. That IP is Mac 3, which
has nothing on 443, so the connection is refused. Pinning the request to the
real edge works, which rules out TCP, TLS and HTTP.

**Root cause.** Mac 1's dnsmasq record for `app.teamX.test` pointed at Mac 3's
IP instead of the Mac 2 edge.

**What was injected** (from Mac 1 on #17). At 17:01:21 IST,
`02_config/phase2/mac1-dns-phase2.sh 10.7.4.108 10.7.30.194 && sudo brew services restart dnsmasq`.
This changed `app.teamX.test` and `api.teamX.test` on the primary only.

**Fix.** At 17:06:05 IST,
`02_config/phase2/mac1-dns-phase2.sh 10.7.4.108 10.7.6.184 && sudo brew services restart dnsmasq`.
Mac 1 reports its live config is byte-identical to
`02_config/phase2/snapshots/dnsmasq-primary-mac1.conf` again.

**Verified from Mac 4** at 17:07:07 IST: both resolvers answer `10.7.6.184`
with TTL 30, `dscacheutil` has `10.7.6.184`, and 4 HTTPS requests (no `-k`)
return `HTTP/2 200` via `mac2-nginx`, alternating B, A, B, A.

## Drill 2: TLS layer (injected on Mac 2)

**Symptom.** At 17:10:01 IST, `curl https://app.teamX.test/api/status` failed
with `SSL certificate problem: self signed certificate` (curl error 60).

**Diagnosis** (`P2F-02_drill2_diagnosis.png`):

| Layer | Check | Result |
|---|---|---|
| 1 DNS | `dig app.teamX.test`, `dig @10.7.30.194 app.teamX.test` | both `A 10.7.6.184`, TTL 30, pass |
| 2 TCP | `nc -vz 10.7.6.184 443` | `succeeded`, pass |
| 3 TLS | `openssl s_client ... -CAfile 02_config/teamX-rootCA.crt` | subject and issuer `O=drill2 self-signed`, `Verify return code: 18`, fails |
| 3 TLS | `openssl x509 -serial -text` on the served cert | SANs right, serial `54F7C238…280D`, not the edge cert |
| 4 HTTP | `curl -k ...` (only to look past TLS) | `HTTP/2 200`, Backend B, `mac2-nginx` |

DNS and TCP pass, so the client reaches the right edge. TLS fails because the
cert isn't signed by teamX-rootCA. It signs itself. The names on it still
match, so this isn't a SAN problem. With `-k` the edge proxies normally, so
nginx's upstreams and both backends are fine. Only the cert/key pair is wrong.

**Root cause.** Mac 2's nginx `ssl_certificate` and `ssl_certificate_key`
pointed at a self-signed pair instead of the cert signed by teamX-rootCA.

**What was injected** (from Mac 2 on #17). Beforehand, a throwaway self-signed
pair was made outside the repo with
`openssl req -x509 -newkey rsa:2048 -nodes -days 2 -keyout drill-selfsigned.key -out drill-selfsigned.crt -subj "/CN=app.teamX.test/O=drill2 self-signed" -addext "subjectAltName=DNS:app.teamX.test,DNS:api.teamX.test"`.
At 17:07:59 IST, only the two TLS lines in the live `teamX.conf` were switched
to that pair, followed by `sudo nginx -t && sudo nginx -s reload`. The team CA
and the real edge key weren't touched.

**Fix.** At 17:11:05 IST,
`02_config/phase2/mac2-edge-phase2.sh 10.7.30.194 10.7.3.254 && sudo nginx -t && sudo nginx -s reload`.
Mac 2 reports its live config is byte-identical to
`02_config/phase2/snapshots/nginx-edge-mac2.conf` again.

**Verified from Mac 4** at 17:12:15 IST: `openssl s_client` shows issuer
`teamX Local Root CA` with `Verify return code: 0 (ok)`, and 4 HTTPS requests
(no `-k`) return `HTTP/2 200` via `mac2-nginx`, alternating A, B, A, B.

## Restored state

- Mac 1 and Mac 3 both answer `app.teamX.test A 10.7.6.184`, TTL 30 (checked
  from Mac 4 at 17:07).
- Mac 2's edge serves the teamX-rootCA cert and alternates A/B (checked from
  Mac 4 at 17:12).
- Mac 4's Wi-Fi DNS is back to `1.1.1.1`, its setting before the drills
  (17:12).

## Things we ran into

- **Homebrew tools on Mac 4 can't reach the LAN from Terminal.** Homebrew's
  `curl` and `openssl` failed with `No route to host` for every `10.7.x.x`
  address, while `/usr/bin/curl`, `/usr/bin/openssl`, `dig` and `nc` worked.
  It looks like macOS's Local Network permission blocking the Homebrew
  binaries, but we haven't confirmed that. Both screenshots use
  `/usr/bin/curl` and `/usr/bin/openssl` for this reason. In a live demo, run
  the `/usr/bin` versions first, before blaming the network.
- **`nginx -s reload` is graceful.** Mac 2 saw a check fired in the same second
  as the restore still get `verify 18`, because an old worker served the
  self-signed cert for a moment. Checks a few seconds later were clean. After a
  reload, wait a moment before deciding the fix didn't work.
- **A broken primary doesn't trigger DNS failover.** macOS only falls back to
  Mac 3 when Mac 1 doesn't answer. A wrong answer from Mac 1 is used as is. So
  in drill 1 the backup resolver, though correct, didn't help.
