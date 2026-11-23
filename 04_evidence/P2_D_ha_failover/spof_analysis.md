# Single point of failure analysis (Extension D)

## What Phase 2 removed

| Failure | Phase 1 result | Phase 2 result | Evidence |
| --- | --- | --- | --- |
| Mac 1 dnsmasq stops | Names stop resolving, service unreachable | Clients fall back to Mac 3 backup DNS after one timeout | `04_evidence/P2_docker_emulation/P2A_backup_dns.txt` |
| Backend A stops | Some requests may fail before nginx marks A down | All requests served by B with HTTP 200; A rejoins after `fail_timeout=10s` | `04_evidence/P2_docker_emulation/P2D_ha_failover.txt` |
| Backend B stops | Same as above | All requests served by A | Same mechanism |

The evidence paths above are Docker emulation runs. Real Mac evidence is pending
under issues P2-10, P2-13 and P2-14.

## What is still a single point of failure

**The nginx edge on Mac 2.** Every HTTPS request terminates there. Both DNS
servers return Mac 2's address, so if Mac 2 or its nginx process stops, every
client fails even though both backends and both DNS servers are healthy.

Extension E shows a manual workaround: change the DNS record to the standby edge
on Mac 4. That is not failover. It needs a person to act, and clients keep
using the dead edge until their cached record expires (up to the 30 second TTL).

Other remaining single points: the Wi-Fi network and its access point; the
team root CA key, which exists only on Mac 2 (losing it means no new
certificates can be issued); and in the Docker emulation, Mac 2 also routes
between the two subnets, so its failure also cuts Mac 1 off from Mac 3 and
Mac 4.

## How to eliminate the edge single point of failure

1. **Shared virtual IP with VRRP (keepalived).** Mac 2 and Mac 4 both run nginx
   and agree on one floating IP. The active edge answers ARP for it; if it stops
   sending VRRP heartbeats, the standby takes the IP within a few seconds. DNS
   never changes, so the TTL does not matter. This needs both edges on the same
   L2 network.
2. **A layer 4 load balancer or ECMP in front of several edges.** A TCP load
   balancer or a router with equal-cost routes spreads connections across both
   edges and health-checks them. This moves the problem to the load balancer,
   which must itself be redundant (cloud load balancers are a managed cluster).
3. **Health-checked DNS failover with multiple A records.** Publish both edges
   and have a health checker remove a dead edge from DNS automatically, with a
   short TTL. Cheapest option, but failover speed is bounded by the TTL and by
   clients that ignore it.

For this project's scale, option 1 is the practical fix: two Macs, one shared
IP, recovery in seconds, and no DNS change.
