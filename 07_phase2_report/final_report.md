# teamX Phase 2 Final Report: Harden, Recover, Troubleshoot

**Status: draft.** Results below are from the live network on 23 November 2026.
Items marked *pending* have not been observed yet, or their evidence is still
in an open pull request. Every evidence path is listed with where it lives
today.

| Mac | Role in Phase 2 | IPv4 (`/19`, gateway `10.7.0.1`) |
| --- | --- | --- |
| Mac 1 | Primary DNS (`dnsmasq`), test client | `10.7.4.108` |
| Mac 2 | Primary HTTPS edge (`nginx`), load balancer | `10.7.6.184` |
| Mac 3 | Backend A (`:3001`), backup DNS | `10.7.30.194` |
| Mac 4 | Backend B (`:3002`), standby HTTPS edge, test client | `10.7.3.254` |

Full table and collection commands: `01_architecture/ip_table.md`.

## 1. What changed from Phase 1

Phase 2 extends the Phase 1 network in place. The Phase 1 configs
(`02_config/dnsmasq-teamX.conf`, `02_config/nginx-teamX.conf`) are kept
unchanged as the Phase 1 record. Every Phase 2 change is made by a script in
`02_config/phase2/`, and each live config is committed as a snapshot under
`02_config/phase2/snapshots/`.

| Area | Phase 1 | Phase 2 | Where |
| --- | --- | --- | --- |
| LAN addresses | Recorded 28 Sep 2026 | All four Macs rechecked; every IPv4 changed by DHCP, and Mac 3's private Wi-Fi MAC changed | `01_architecture/ip_table.md`, `P2L-01` to `P2L-04` |
| DNS | One resolver (Mac 1), `local-ttl=60` | Primary on Mac 1 and backup on Mac 3 with identical records, `local-ttl=30` | `snapshots/dnsmasq-primary-mac1.conf`, `snapshots/dnsmasq-backup-mac3.conf` |
| Edge | Mac 2 `nginx` | Same config, refreshed to the Phase 2 backend IPs by `mac2-edge-phase2.sh`; the Phase 1 certificate is reused, not regenerated | `snapshots/nginx-edge-mac2.conf` |
| Backend access | Ports 3001 and 3002 open to any host | `pf` anchor `teamX-backend` on Mac 3 and Mac 4: pass `lo0` and the edge IPs, `return-rst` for everyone else, with a scripted rollback | `pf-backend-isolate.sh`, `pf-backend-rollback.sh`, `snapshots/pf-mac3-3001.conf` |
| Standby edge | None | `nginx` on Mac 4 (`X-Edge: mac4-standby-nginx`) proxying to Mac 3 `:3001` and local `127.0.0.1:3002` | `mac4-standby-edge.sh`, `snapshots/nginx-standby-mac4.conf` |
| Standby TLS | None | Mac 4 generated its own key and CSR; Mac 2 signed it with `teamX-rootCA` (serial `41C5F4AD…5F20`, valid to 23 Nov 2027). Neither private key left its Mac | `standby-tls-notes.md`, `app.teamX.test-standby.{csr,crt}` |
| Diagnosis | Ad hoc | One-page 4-layer runbook (DNS, TCP and `pf`, TLS, HTTP) | `troubleshooting_runbook.md` |

The passive health checks were already in Phase 1 (`max_fails=1
fail_timeout=10s`, `proxy_connect_timeout 2s`, `proxy_next_upstream error
timeout http_502 http_503`). Phase 2 keeps them and proves they work
(Extension D).

Each Phase 2 script has a test under `02_config/phase2/tests/` that checks its
input validation and rendered config.

## 2. Resilience tests and results

### Extension A: backup DNS

| Test | Result | Evidence |
| --- | --- | --- |
| Backup `dnsmasq` on Mac 3 answers with the same record | Listens on `10.7.30.194:53`; `app` and `api.teamX.test` return `10.7.6.184`, TTL 30 | `04_evidence/P2_A_backup_dns/P2A-01_mac3_backup_dnsmasq_running.png` |
| Client with both resolvers, primary up | Mac 4 (resolvers Mac 1 then Mac 3) gets its answer from `10.7.4.108`, HTTPS `200` | `P2A-03_mac4_dual_dns_primary_up.png` (pending, PR #45) |
| Primary stopped | `dig` reports `SERVER: 10.7.30.194` with the same record, and HTTPS still returns `200`. `dig` asks the resolver directly, so this answer came from the backup, not a cache | `P2A-04_mac4_backup_failover_primary_stopped.png` (pending, PR #45) |
| Backup logged the failover lookups | Mac 3's query log shows `app.teamX.test` from `10.7.3.254` answered with `10.7.6.184` | `04_evidence/P2_A_backup_dns/P2A-02_mac3_backup_query_log.png` |
| Primary restored | Answers from `10.7.4.108` again | `P2A-05_mac4_primary_restored.png` (pending, PR #45) |

### Extension B: TTL and controlled record change

*Pending (#10).* The `local-ttl=30` setting is in place on both resolvers
(`dig` shows TTL 30 in `P2A-01`). The record change, the cached answer until
expiry, and the manual flush (`P2B-01` to `P2B-03`) have not been captured
yet.

### Extension C: service isolation

| Test | Result | Evidence |
| --- | --- | --- |
| Mac 3 anchor loaded, Phase 1 `pf.conf` backed up first | Rules pass `lo0`, Mac 2 and Mac 4, reset others on 3001; backup saved 15:34 | `04_evidence/P2_C_service_isolation/P2C-01_mac3_pf_anchor_loaded.png` |
| Mac 4 anchor loaded | Rules pass `lo0` and Mac 2, reset others on 3002; `Status: Enabled` | `04_evidence/P2_C_service_isolation/P2C-02_mac4_pf_anchor_loaded.png` |
| Client blocked, edge still works | From Mac 1 at 15:58:38, direct connections to 3001 and 3002 get a TCP reset while `https://app.teamX.test` returns `200` | `P2C-03_mac1_direct_backends_blocked_edge_ok.png` (pending, PR #43) |
| Edge allowed | From Mac 2 at 15:59:46, both backends return `200` directly | `P2C-04_mac2_direct_backends_allowed.png` (pending, PR #44) |
| Rollback | Mac 3: anchor flushed, 0 rules, `/etc/pf.conf` identical to the Phase 1 backup | `04_evidence/P2_C_service_isolation/P2C-05_mac3_pf_rollback.png` |
| Rollback | Mac 4: anchor flushed, pf disabled again (its Phase 1 state), `/etc/pf.conf` matches the Phase 1 backup, Backend B still answers `200` | `04_evidence/P2_C_service_isolation/P2C-06_mac4_pf_rollback.png` |

The reset in `P2C-03` is `pf`, not a stopped service: Mac 2's access log shows
Backend A answering from 15:57:53, before that capture.

Mac 4 is allowed on 3001 because the standby edge proxies to Backend A. Mac 4
is also a test client, so isolation checks run from Mac 1 only.

### Extension D: high availability failover

| Test | Result | Evidence |
| --- | --- | --- |
| Both backends up | Six requests from Mac 1 alternate A, B, A, B, A, B | `P2D-01_mac1_both_backends_up.png` (pending, PR #43) |
| Backend A stopped | Six requests, all `200` from Backend B | `P2D-02_mac1_backendA_stopped_all_B.png` (pending, PR #43) |
| Backend A restored | A and B alternate again | `P2D-03_mac1_backendA_restored_AB.png` (pending, PR #43) |
| Edge view of the same behaviour | Mac 2's access log: A/B at 15:40:23; the first drill request at 15:45:41 found A already down, so nginx retried B in the same request (`(502, 200)`) and the client got `200`; A back at 15:46:50 | `P2D-04_mac2_edge_failover_access_log.png` (pending, PR #44) |
| No client errors during the drill | 180 HTTPS requests at one per second through Mac 2 while A was stopped and restarted: all 180 returned `200` (A 61, B 119) | Recorded in PR #44 |
| Single point of failure | Mac 2's `nginx` (see Section 4, Extension D) | `spof_analysis.md` (pending, PR #44) |

One failure was observed and is recorded: at 15:56:08 to 15:56:09 the edge
returned `502` five times. Both backends were unavailable at once, because
Backend A was stopped for a drill while Mac 4's `pf` anchor was being loaded.
With no healthy upstream, nginx had nothing to fail over to. Details:
`P2D_note_502_burst.md` (pending, PR #43).

### Extension E: controlled edge migration

| Test | Result | Evidence |
| --- | --- | --- |
| Standby edge serves trusted HTTPS | `openssl verify` against `02_config/teamX-rootCA.crt` returns `OK`; `nginx` listens on `*:443` | `04_evidence/P2_E_edge_migration/P2E-01_mac4_standby_nginx_and_cert_verify.png` |
| Standby proxies to both backends | Four requests without `-k` alternate A (`10.7.30.194:3001`) and B (`127.0.0.1:3002`), `x-edge: mac4-standby-nginx` | `04_evidence/P2_E_edge_migration/P2E-01b_mac4_standby_commands_and_both_backends.png` |
| DNS cutover to Mac 4 and TTL transition | *Pending (#16)* | |

### Extension F: troubleshooting

The runbook is in place (`02_config/phase2/troubleshooting_runbook.md`). The
two mock fault drills are *pending (#17)*.

## 3. Troubleshooting findings

**Method.** Work up the stack and stop at the first failing layer: DNS
(`dig` against each resolver), then TCP and `pf` (`ping`, `nc -vz`,
`pfctl -sr`), then TLS (`openssl s_client`, verify return code and SAN), then
HTTP (`curl` headers, `X-Edge`, `X-Upstream-Addr`, the edge access log).
After a fix, re-run every check from that layer up.

**Mock drills (#17).** *Pending.*

**Faults met while building Phase 2.** These were real, not injected, and each
was found by the same layer order:

| Symptom | Layer | Cause | Fix |
| --- | --- | --- | --- |
| Phase 1 IPs no longer reachable | Network | DHCP gave all four Macs new addresses; Mac 3's private MAC also changed | Rechecked every row (`P2L-01` to `P2L-04`), then re-ran each script with the new IPs |
| `ifconfig en0` shows `ether 02:00:00:00:00:00` | Network | Newer macOS hides the real MAC from apps | Read it from the DHCP packet (`ipconfig getpacket en0`, `chaddr`) |
| Signing step fails with `unknown option -ext` | TLS | `/usr/bin/openssl` is LibreSSL | Put Homebrew `openssl@3` first on `PATH` before signing |
| HTTPS through Mac 2 returns `502` with `x-upstream-addr` listing both backends | HTTP, caused at TCP | Neither backend was running; `nc -vz` showed `Connection refused` while `ping` worked | Started both backends; requests alternated A and B |
| `nginx -s reload` fails after a restart | HTTP | `nginx` was not running, so there was nothing to reload | Start it with `sudo nginx` after `sudo nginx -t` |
| Five `502`s at 15:56 | HTTP, caused at TCP and `pf` | Two planned changes overlapped: a backend stopped while the other's `pf` anchor loaded | Change one thing at a time; check both upstreams before a drill |

One diagnosis was wrong and is worth recording. We concluded that `curl -I`
(HEAD) gets `501` from the backends, based on a test against a stand-in
server. The real backend has `do_HEAD = do_GET`
(`03_backend_code/server.py:125`), and live HEAD requests return `200`. The
lesson: verify a hypothesis against the real system before acting on it.

## 4. Learning summary

**Extension A, backup DNS.** A client lists two resolvers and tries the
second only when the first does not answer, so a DNS outage becomes a
fallback instead of a failed lookup. With Mac 1 stopped, `dig` on Mac 4
showed the answer coming from Mac 3 (`SERVER: 10.7.30.194`), and Mac 3's
query log recorded the same lookups. This is
different from an application failure. When DNS fails, the name stops
resolving, so `dig` fails before any connection is attempted. When a backend
fails, the name still resolves and TCP to the edge works, but the request
fails or is retried at the HTTP layer. Knowing which one you have decides
where to look.

**Extension B, TTL and record change.** The TTL is a promise about how long
any resolver or client may reuse an answer. A 30 second TTL means a record
change takes up to 30 seconds to reach every client, and a client that cached
the old answer keeps using it until then; flushing the cache skips the wait
on that one client. Production teams lower the TTL well before a planned
migration, so the cutover converges quickly, then raise it again afterwards
to cut query load. (Live observation pending, #10.)

**Extension C, service isolation.** Before Phase 2 anyone on the LAN could
skip the edge and talk to a backend directly, bypassing TLS and load
balancing. A `pf` anchor that passes only the edge's address and `lo0`, and
answers everyone else with a reset, makes the edge the only way in. Using a
named anchor plus a saved copy of `/etc/pf.conf` made the change reversible
in one step, which matters on machines we do not fully own. Allowing the
standby edge as well showed that firewall rules have to follow the
architecture: every machine that legitimately proxies must be listed.

**Extension D, high availability.** nginx detects failure passively: a
connection error marks a backend down for `fail_timeout`, and
`proxy_next_upstream` retries the same request on the other backend, so the
client still gets `200`. The log shows this as two upstreams on one line,
`(502, 200)`. After the timeout nginx tries the failed backend again, which is
how it noticed Backend A coming back. The remaining single point of failure is
Mac 2's `nginx`. Both resolvers answer with its address, so if it stops,
every request fails even with both backends healthy. Removing it needs a
second active edge plus a way to move traffic automatically: a floating
virtual IP (VRRP), a layer 4 balancer in front, or DNS failover driven by
health checks. The burst of `502`s also showed the limit of passive checks:
when both upstreams are down, there is nothing to fail over to.

**Extension E, edge migration.** A standby edge has to present a certificate
clients already trust, so Mac 4 sent a CSR and Mac 2 signed it with the
existing team CA. No private key moved, and no client needed a new CA. The
cutover itself is a DNS change, so it inherits Extension B's behaviour:
clients holding the old answer keep reaching Mac 2 until their TTL expires,
while new lookups reach Mac 4. Because the move is driven by TTL, it is a
planned migration tool, not instant failover. (Live cutover pending, #16.)

**Extension F, troubleshooting.** Diagnosing in a fixed order, DNS then TCP
then TLS then HTTP, stops guessing: the first failing check names the layer.
Our own faults showed why the order matters. A `502` is reported at the HTTP
layer, but its cause was at TCP (nothing listening, or a `pf` change). A
failed signing step looked like a TLS problem, but the cause was the wrong
`openssl` binary. The runbook turns this into a repeatable checklist.
(Mock drills pending, #17.)

## Pending before this report is final

- [ ] Ext A failover screenshots merged (PR #45)
- [ ] Ext B TTL and flush captured (#10)
- [x] Ext C Mac 4 anchor and rollback (PR #42, merged)
- [ ] Ext C and D Mac 1 evidence merged (PR #43)
- [ ] Ext C and D Mac 2 evidence and SPOF analysis merged (PR #44)
- [ ] Ext E DNS cutover (#16)
- [ ] Ext F mock drills (#17) and architecture update (#18)
