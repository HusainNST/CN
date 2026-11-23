# Evidence index

Where to find each piece of evidence, by step of the Final Demonstration
Sequence (`CN_Project_Doc.pdf` Section 8) and by deliverable. Phase 1 folders
are `A_lan` to `H_failures`; Phase 2 folders start with `P2_`. Screenshot names
start with their folder's letter and a number, then the Mac that took them.

These files are saved evidence from the dates in the reports. They don't prove
the live network works today.

## Demonstration steps

| # | Step | Evidence |
| --- | --- | --- |
| 1 | Topology and IP/service inventory | `../01_architecture/topology.png`, `../01_architecture/ip_table.md`, `../01_architecture/architecture_doc.md` |
| 2 | All Macs on the private LAN | Phase 2 IPs: `P2_lan_recheck/P2L-01` to `P2L-04` (one ping-all per Mac). Phase 1: `A_lan/A-01` to `A-08` |
| 3 | `dig app.teamX.test` from a client | `B_dns/B-03_mac4_dig_app.png`, `B_dns/B-04_mac1_dig_api_and_nslookup.png`; with both Phase 2 resolvers: `P2_A_backup_dns/P2A-03_mac4_dual_dns_primary_up.png` |
| 4 | HTTPS by name, no certificate warning | `E_tls/E-02_mac1_curl_verbose_tls.png`, `E_tls/E-03_mac4_curl_verbose_tls.png`, browser: `D_loadbalancing/D-05_mac4_browser_backendA.png` and `D-05_mac4_browser_backendB.png` |
| 5 | Load balancing, `X-Backend` A and B alternating | `D_loadbalancing/D-04_mac4_xbackend_alternating.png`, edge log: `D_loadbalancing/D-03_mac2_access_log_alternating.png` |
| 6 | Wireshark: DNS, TCP handshake, TLS handshake | Captures: `G_protocol_flow/G_capture3_tls12.pcapng` (TLS 1.2), `G_capture2_tls13.pcapng` (TLS 1.3). Marked screenshots: `G_protocol_flow/G-01` to `G-08` |
| 7 | HTTP headers and caching (`304` or cache hit) | `F_caching/F-01_cache_revalidation.png`, `F_caching/F-02_browser_cache_hit.png` |
| 8 | One backend stopped, service continues | `H_failures/H-03a` to `H-03c` (Mac 3), edge log: `H_failures/H-06` and `H-07`; Phase 2 repeat: `P2_D_ha_failover/P2D-01` to `P2D-04` |
| 9 | Phase 2 DNS and resilience (Ext A, B, E) | Backup DNS: `P2_A_backup_dns/`. TTL and flush: `P2_B_dns_ttl/`. Edge cutover: `P2_E_edge_migration/` and `P2E_notes.md` |
| 10 | Diagnose an injected fault | Method: `../02_config/phase2/troubleshooting_runbook.md`. Practice drills: `P2_F_troubleshooting/drill_findings.md`, `P2F-01`, `P2F-02` |
| 11 | Individual viva | `../01_architecture/architecture_doc.md`, `../07_phase2_report/final_report.md` |

## Phase 2 extensions

| Extension | Folder | Start with |
| --- | --- | --- |
| A, backup DNS | `P2_A_backup_dns/` | `P2A-04_mac4_backup_failover_primary_stopped.png` |
| B, TTL and cache flush | `P2_B_dns_ttl/` | `P2B-02_mac4_ttl_cached_then_expired.png` |
| C, service isolation (`pf`) | `P2_C_service_isolation/` | `P2C-03_mac1_direct_backends_blocked_edge_ok.png` |
| D, HA failover | `P2_D_ha_failover/` | `P2D-02_mac1_backendA_stopped_all_B.png`, `spof_analysis.md`, `P2D_note_502_burst.md` |
| E, edge migration | `P2_E_edge_migration/` | `P2E_notes.md`, then `P2E-03` and `P2E-04` |
| F, troubleshooting | `P2_F_troubleshooting/` | `drill_findings.md` |

## Phase 1 failure scenarios (`H_failures/`)

| Failure | Evidence |
| --- | --- |
| Wrong DNS server | `H-01_wrong_dns_server.png`, `H-01a`, `H-01b` (restored) |
| Wrong DNS record | `H-02_wrong_dns_record.png`, `H-02_wrong_dns_record_https_failure_mac1.png`, restored: `H-02_wrong_dns_record_https_restored_mac4.png`, `H-02_wrong_dns_record_restored_mac4.jpeg` |
| One backend stopped | `H-03a` to `H-03c`, `H-06`, `H-07` |
| Both backends stopped | `H-04_both_backends_down_502.png` |
| Wrong destination port | `H-05_wrong_port.png`, `H-05_wrong_port.pcapng` |

## Other deliverables

| Deliverable | Location |
| --- | --- |
| Architecture document (updated for Phase 2) | `../01_architecture/architecture_doc.md`, `topology.png`, `request_flow.png` |
| Phase 1 configs | `../02_config/dnsmasq-teamX.conf`, `../02_config/nginx-teamX.conf`, `../02_config/tls_setup_notes.md` |
| Phase 2 configs | Scripts in `../02_config/phase2/`, live snapshots in `../02_config/phase2/snapshots/`, standby TLS: `../02_config/phase2/standby-tls-notes.md` |
| Firewall rules | `../02_config/phase2/snapshots/pf-mac3-3001.conf`, `pf-mac4-3002.conf` |
| Backend source and launch | `../03_backend_code/server.py`, `../03_backend_code/README.md` |
| Phase 2 final report | `../07_phase2_report/final_report.md` |

## Gaps in the numbering

Some numbers were never used, so nothing is missing at these spots: `A-07`
(Mac 3's ping is in `A-03_mac3_network_ping.png`), `C-03` and `C-05`.
