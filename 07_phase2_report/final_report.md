# Phase 2 final report: harden and recover

**Status: draft.** Every result below comes from the Docker emulation in
[05_docker_lab](../05_docker_lab/README.md), where four containers play
Mac 1 to Mac 4. The live runs on the real Macs (issues P2-07 to P2-17) are
pending. Replace or add the real `04_evidence/P2_*` screenshots before
submission, and keep the emulation results labelled as emulation.

## 1. What changed from Phase 1

| Area | Phase 1 | Phase 2 | Config |
| --- | --- | --- | --- |
| DNS | One dnsmasq on Mac 1, TTL 60 | Primary on Mac 1 and backup on Mac 3 with identical records, TTL 30; clients list both | `02_config/phase2/mac1-dns-phase2.sh`, `mac3-backup-dns.sh` |
| Record changes | Manual edit | Script reruns with a new edge IP, the same on both servers | same scripts |
| Backend access | Any LAN host could reach ports 3001 and 3002 | pf anchor `teamX-backend` allows only the edge (and loopback), sends TCP RST to everyone else, with a saved rollback | `pf-backend-isolate.sh`, `pf-backend-rollback.sh` |
| Edge | nginx on Mac 2 with passive health checks | Same edge, IP refresh script; single point of failure documented | `mac2-edge-phase2.sh`, [spof_analysis.md](../04_evidence/P2_D_ha_failover/spof_analysis.md) |
| Standby edge | None | nginx on Mac 4 with its own key, certificate signed by the team root CA from a CSR | `mac4-standby-edge.sh`, [standby-tls-notes.md](../02_config/phase2/standby-tls-notes.md) |
| Diagnosis | Ad hoc | Four layer runbook: DNS, TCP and pf, TLS, HTTP | [troubleshooting_runbook.md](../02_config/phase2/troubleshooting_runbook.md) |

## 2. Resilience tests and results

| Test | Expected | Emulation result | Evidence |
| --- | --- | --- | --- |
| Primary DNS stopped | Clients resolve through the backup | Mac 4 resolved `app.teamX.test` through Mac 3 after one 2 s timeout; HTTPS 200; Mac 3 log shows Mac 4's query | `P2A_backup_dns.txt` |
| Both DNS servers stopped | Name resolution fails | `curl: (6) Could not resolve host` | `P2A_backup_dns.txt` |
| Both backends stopped | Name resolves, service fails | DNS answer correct, HTTP 502 from the edge | `P2A_backup_dns.txt` |
| Record changed, TTL 30 | Old answer cached until expiry | Cache kept the old IP while the TTL counted 30, 24, 19, 14, 8, 3, then switched | `P2B_dns_ttl.txt` |
| Manual cache flush | New answer at once | Flush switched the answer immediately | `P2B_dns_ttl.txt` |
| pf isolation on | Clients refused, edge allowed | Mac 1 and Mac 4 refused on 3001 and 3002; Mac 2 got 200 from both; HTTPS through the edge 200 | `P2C_service_isolation.txt` |
| pf rollback | Direct access restored | Mac 1 direct request to 3001 returned 200 | `P2C_service_isolation.txt` |
| Backend A stopped | All traffic to B, no errors | Six of six `X-Backend: B`, all 200 | `P2D_ha_failover.txt` |
| Backend A restarted | Balancing resumes | A/B alternation after `fail_timeout` (10 s) | `P2D_ha_failover.txt` |
| DNS cutover to standby | Cached clients briefly on old edge | Same second: cached Mac 1 got `mac2-nginx`, fresh Mac 4 got `mac4-standby-nginx`; Mac 1 moved after 30 s with trusted TLS and A/B balancing | `P2E_edge_migration.txt` |
| Cutover rollback | Back to Mac 2 | `X-Edge: mac2-nginx` | `P2E_edge_migration.txt` |

All transcripts are in `04_evidence/P2_docker_emulation/`.

One issue was found and fixed while testing: the emulation's firewall rollback
first left the isolation chain in place. The saved backup did not contain the
filter table, and `iptables-restore` only resets tables in its input. The
transcript caught it because the post-rollback direct request was still
refused. The rollback now removes the chain explicitly. The macOS
`pf-backend-rollback.sh` restores the whole `/etc/pf.conf` and flushes the
anchor, so it does not have this gap.

## 3. Troubleshooting findings

Diagnosis order: DNS, then network and TCP (including pf), then TLS, then
HTTP and backends. Each layer depends on the one below, so the first failing
layer is the fault. Two drills, details in
[drill_findings.md](../04_evidence/P2_F_troubleshooting/drill_findings.md):

1. **Wrong A record on the primary.** Looked like a TCP connect failure. Layer 1
   showed the primary and backup disagreeing. The backup did not help, because a
   wrong answer is still an answer.
2. **pf allowing the wrong edge IP.** Users saw only 200s; the clue was every
   response coming from B. Layer 2 from the edge showed RST on 3001, and the
   anchor listed a mistyped IP. Failover hides faults, so monitoring must
   watch backend health, not only user errors.

## 4. Learning summary

**Extension A, backup DNS.** A second resolver removes DNS as a single point of
failure, but only for a server that stops answering. Clients try resolvers in
order and move on after a timeout, so failover costs a delay of seconds, not an
outage. A DNS failure and an application failure look different: when DNS
fails, the name does not resolve at all; when a backend fails, the name resolves and
the edge returns 502. Checking `dig` first tells you which one you have.

**Extension B, TTL.** The TTL is how long a client may reuse an answer without
asking again. Lowering it to 30 seconds made the cached answer visible: after
the record changed, the client kept the old address until the TTL ran out,
while the server already gave the new one. Flushing the cache skips the wait.
In production, teams lower the TTL well before a migration, so the cutover
takes effect quickly, then raise it again afterwards.

**Extension C, service isolation.** The backends should only be reachable
through the edge, where TLS, logging and load balancing happen. A pf anchor
allows the edge's IP and resets every other connection on the backend port.
The rule must name the address the backend actually sees, which with routing
is the edge's server side interface. A rollback copy made the change safe to
undo.

**Extension D, high availability.** nginx's passive health check marks a backend
down after one failed attempt and retries the next upstream in the same
request, so users see no errors. After `fail_timeout` it tries the backend
again with real traffic, which is why recovery shows a couple of B responses
before A returns. The remaining single point of failure is the edge on Mac 2.
A shared virtual IP with VRRP would remove it.

**Extension E, edge migration.** Moving the edge is a DNS change plus a second
edge that clients already trust. Signing Mac 4's CSR with the team root CA
meant no client needed a new certificate, and no private key left the machine
that uses it. The TTL decides how long old clients keep using the old edge,
so the old edge must stay up until the TTL has passed.

**Extension F, troubleshooting.** Working up the layers stops guessing. The
fastest checks are comparing what each DNS server says and testing the
backend ports from the edge itself. The pf drill showed that a working
service can still be broken underneath, and only the response headers
revealed it.
