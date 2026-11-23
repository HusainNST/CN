# Extension D: remaining single point of failure

## What the Phase 2 design covers

These are the design's answers to each failure. Live proof for each row: row 1
is `P2D-04` (below), row 2 is `P2A-04` (#45: Mac 3 answered at 16:05:20 with
Mac 1 stopped, HTTPS still `200`), and row 3 is `P2C-01`, `P2C-02` and
`P2C-04`.

| Failure | What keeps the service up | Where |
| --- | --- | --- |
| One backend stops | Mac 2 nginx marks it down after one failed attempt (`max_fails=1 fail_timeout=10s`) and retries the request on the other backend (`proxy_next_upstream error timeout http_502 http_503`) | `02_config/phase2/mac2-edge-phase2.sh` |
| Primary DNS on Mac 1 stops | Clients fall back to the backup `dnsmasq` on Mac 3 (Extension A) | P2-07, P2-08 |
| Clients reach a backend directly | `pf` on Mac 3 and Mac 4 allows ports 3001 and 3002 only from the edges and loopback: Mac 2 on both, Mac 4's standby edge on 3001, and `lo0` (Extension C) | P2-11, P2-12 |

The backend tier and the DNS tier each have two copies. The edge tier does not.

## The remaining SPOF: nginx on Mac 2

Both DNS servers answer `app.teamX.test` and `api.teamX.test` with one
address, Mac 2's. Mac 2 is also the only machine that terminates TLS and load
balances. If nginx on Mac 2 stops, or Mac 2 leaves the network, every client
gets a connection refused or a timeout, even though both backends are healthy.
Nothing in the design notices this or reacts to it automatically.

The Mac 4 standby edge from Extension E does not remove this SPOF. It is a
manual cutover: a person edits the DNS record, and clients keep using the old
answer until their cached record expires (`local-ttl=30`). Recovery takes as
long as it takes someone to notice the outage, plus up to 30 seconds of TTL.

## Ways to eliminate it

| Option | How it works | What it would need here | Trade off |
| --- | --- | --- | --- |
| Floating virtual IP (VRRP, for example `keepalived`) | Mac 2 and Mac 4 share one virtual IP. The active edge answers ARP for it; if its heartbeats stop, the standby claims the IP within seconds. DNS points at the virtual IP, so clients never change address. | A spare address in `10.7.0.0/19`, the same nginx config and certificate on both edges, and a VRRP daemon. `keepalived` targets Linux, so on these Macs it would need a Linux VM or a different tool. Campus Wi-Fi may also block VRRP multicast or a second IP per client. | Fastest failover and no DNS caching delay. Needs both edges on the same L2 segment. |
| Layer 4 load balancer or ECMP in front of the edges | A TCP load balancer, or a router spreading flows with equal cost routes, sends connections to whichever edges pass its health check. | A device or service in front of Mac 2 and Mac 4. We do not control the campus router, so this is the cloud answer (a managed network load balancer) rather than a lab one. | Both edges serve traffic at once. The L4 balancer is now the component that must itself be redundant, which managed cloud balancers handle for you. |
| Health checked DNS failover across several edges | DNS returns both edges, or only the healthy ones, and a health check removes an edge from the answer when it fails. This automates the Extension E cutover. | A checker that probes `https://<edge>/` and rewrites the `dnsmasq` record, or a DNS service with built in health checks (for example Route 53 failover records). | Simple, and works across networks. Recovery is still bounded by TTL and by clients that cache longer than the TTL. |

For this lab, health checked DNS failover is the smallest step from what
Extension E already does. A floating virtual IP gives the fastest recovery on
one LAN. In the cloud, a managed load balancer covers the edge tier.

## Other single points we accept

- The Rishihood Learners Wi-Fi and its gateway `10.7.0.1` carry every
  connection. Removing that needs a second network path, which is out of scope.
- `teamX-rootCA.key` lives only on Mac 2. Losing it stops new certificates
  from being signed, but certificates already issued keep working, so it does
  not cause an outage.

## Evidence

- Pending: `P2D-01_mac1_both_backends_up.png`,
  `P2D-02_mac1_backendA_stopped_all_B.png` and
  `P2D-03_mac1_backendA_restored_AB.png`: client side failover and recovery
  from Mac 1 (P2-13).
- `P2D-04_mac2_edge_failover_access_log.png`: captured 23 Nov 2026. Mac 2's
  `teamX_access.log` shows A/B alternation at 15:40:23. The first logged request
  of the drill, at 15:45:41, found Backend A already down: nginx got 502 from A
  and retried B, and the client got 200. Requests to 15:45:49 went to B. At
  15:46:36, after `fail_timeout`, nginx tried A again, got 502 and retried B.
  A/B alternation resumed at 15:46:50. The grep shows those windows only, not
  the 15:45:50 to 15:46:34 stretch.
