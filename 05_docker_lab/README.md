# Phase 2 Docker emulation

Four Docker containers stand in for Mac 1 to Mac 4, with the same roles as the
real project network. The lab lets one person rehearse and check every Phase 2
extension (A to F) when the other Macs are not available.

**Evidence from this lab is emulation evidence.** It shows that the Phase 2
scripts and configs behave correctly. It does not prove that the real Macs on
the project LAN were configured. Real Mac screenshots in `04_evidence/P2_*`
are still required by the GitHub issues.

## What is real and what is emulated

| Part | In the lab |
| --- | --- |
| dnsmasq, nginx, backend configs | Rendered by the repo's `02_config/phase2/*.sh` scripts with `--render-only` |
| Backend code | `03_backend_code/server.py`, mounted read-only, unchanged |
| pf isolation (Extension C) | The anchor rendered by `pf-backend-isolate.sh`, applied as equivalent Linux iptables rules by `pf-anchor-to-iptables.sh` |
| Client DNS cache (macOS mDNSResponder) | A dnsmasq cache on Mac 1 and Mac 4 at `127.0.0.53`, primary then backup resolver, flushed with SIGHUP |
| TLS root CA | A throwaway lab CA created inside the `mac2` container. The real `teamX-rootCA.key` is never used. |
| nginx | 1.27.3 with `worker_processes 1`, which matches Homebrew's default on the Macs |

## Subnet plan

The lab splits `10.77.0.0/24` into four `/26` subnets. A `/26` keeps 26 network
bits, leaving 6 host bits: 2^6 = 64 addresses, 62 usable after the network
and broadcast addresses.

| Subnet | Network | Usable hosts | Broadcast | Members |
| --- | --- | --- | --- | --- |
| Client LAN | `10.77.0.0/26` | `.1` to `.62` | `.63` | Mac 1 `.10`, Mac 2 client side `.20` |
| Server LAN | `10.77.0.64/26` | `.65` to `.126` | `.127` | Mac 2 server side `.70`, Mac 3 `.80`, Mac 4 `.90` |
| Spare | `10.77.0.128/26` | `.129` to `.190` | `.191` | unused |
| Spare | `10.77.0.192/26` | `.193` to `.254` | `.255` | unused |

Mac 2 has one interface in each subnet and forwards packets between them, so it
is the router as well as the edge. DNS records point clients at Mac 2's client
side address (`10.77.0.20`). The backend firewall allows Mac 2's server side
address (`10.77.0.70`), because that is the source address the backends see.

The real Macs share one flat `/19` Wi-Fi network. The lab adds the subnet
split on purpose. It shows that the firewall rules still work when traffic
crosses a router, and it makes Mac 2 an even larger single point of failure
(see [spof_analysis.md](../04_evidence/P2_D_ha_failover/spof_analysis.md)).

## Run it

Requires Docker with Compose v2.

```sh
cd 05_docker_lab
./run-phase2.sh            # fresh lab, runs Extensions A to F, about 3 minutes
```

The script writes one timestamped transcript per extension to
`04_evidence/P2_docker_emulation/` and the rendered configs to
`05_docker_lab/snapshots/`.

To explore by hand:

```sh
docker compose up -d --build
docker compose exec mac1 bash
lab                        # lists the service commands
docker compose down -v     # remove the lab
```

## Transcripts and the issues they cover

| Transcript | Extension | Issues |
| --- | --- | --- |
| `P2A_backup_dns.txt` | A, backup DNS, and DNS failure versus app failure | P2-07, P2-08, P2-10 |
| `P2B_dns_ttl.txt` | B, TTL countdown and manual flush | P2-10 |
| `P2C_service_isolation.txt` | C, pf isolation and rollback | P2-11, P2-12, P2-13, P2-14 |
| `P2D_ha_failover.txt` | D, failover and recovery with edge log | P2-13, P2-14 |
| `P2E_edge_migration.txt` | E, CSR signing, standby edge, DNS cutover, rollback | P2-04, P2-05, P2-15, P2-16 |
| `P2F_troubleshooting_drills.txt` | F, two scripted fault drills | P2-17 |

## Limits

- Containers run Linux, not macOS. Commands such as `dscacheutil`, `lsof` and
  `pfctl` have Linux stand-ins (`getent`, `ss`, `iptables`).
- Faults in the drills are injected by the script, so the drills are not blind.
- Real IPs, Wi-Fi behaviour and macOS firewall prompts are not exercised.
