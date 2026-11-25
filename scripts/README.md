# Live Demo Scripts

One wrapper script per machine plus a shared 4-layer troubleshooting script. Every script sources `scripts/env.sh` and delegates Phase 2 config changes to the existing scripts under `02_config/phase2/`.

## Before the demo (DHCP check)

Campus DHCP may assign new IPs when the four Macs reconnect. Check `ipconfig getifaddr en0` on each Mac and update the four IP lines in `scripts/env.sh` once (or override them on the command line with `MAC1_IP=... MAC2_IP=...`).

## Quick map to the 11-step demo sequence

| Demo step | Machine | Command |
| --- | --- | --- |
| 1–2. LAN inventory & pings | Any / Mac 4 | `./scripts/mac4_demo.sh info` (or `mac1_demo.sh info`, etc.) |
| 3. Private DNS resolution | Mac 1 | `./scripts/mac1_demo.sh status` |
| 4. Trusted HTTPS by name | Mac 2 | `./scripts/mac2_demo.sh check-https` |
| 5. Load balancing (A/B) | Mac 2 | `./scripts/mac2_demo.sh check-lb` |
| 6. Wireshark captures | Mac 4 | `./scripts/mac4_demo.sh wireshark-filters` |
| 7. HTTP caching (200 / 304) | Mac 3 | `./scripts/mac3_demo.sh check-cache` |
| 8. Stop Backend A failover | Mac 3 + Mac 2 | `Ctrl+C` on `./scripts/mac3_demo.sh start-backend`, then `./scripts/mac2_demo.sh check-lb` |
| 9a. Ext A backup DNS | Mac 1 + Mac 3 | `./scripts/mac1_demo.sh stop-dns`, watch `./scripts/mac3_demo.sh dns-logs`, then `start-dns` |
| 9b. Ext B TTL & cache flush | Mac 4 | `./scripts/mac4_demo.sh check-ttl`, then `./scripts/mac4_demo.sh flush-dns` |
| 9c. Ext C `pf` isolation | Mac 3, Mac 4, Mac 1, Mac 2 | `pf-on` on Mac 3/4, `check-isolation` on Mac 1, `check-backends` on Mac 2, then `pf-off` |
| 9d. Ext E edge cutover | Mac 4, Mac 1, Mac 3 | `standby-start` on Mac 4, `cutover-standby` on Mac 1/3, then `cutover-primary` + `standby-stop` |
| 10. Ext F injected fault | Any client | `./scripts/troubleshoot.sh` |

Run any script with no arguments to see all its subcommands.
