# Phase 1 team checklist — build, prove, and submit

This is the shared progress page for the four Phase 1 role guides. It follows CN_Project_Doc.pdf, sections 3–6, Section 8 steps 1–8, Section 9, and the Review 1 marks. It does not include Phase 2.

**How to use it:** anyone may tick a task once they have checked the result. Write the evidence path or date beside the item. A source file existing does not prove a service works on the LAN. Use the person guides for commands and detailed instructions.

Use the same private Wi-Fi/hotspot on all four Macs, keep IPs stable during the lab, turn off client isolation, and allow project ports through macOS Firewall. For screenshots, show the terminal prompt, run date before the command, and keep the whole window and full output visible. Save Wireshark screenshots and the original .pcapng capture.

Individual instructions: [Navodit / Mac 1 — DNS and client](navodit_mac1.md), [Sarvesh / Mac 2 — edge, load balancer, and TLS](sarvesh_mac2.md), [Trishit / Mac 3 — Backend A, caching, and architecture](trishit_mac3.md), and [Husain / Mac 4 — Backend B, client, and packet capture](husain_mac4.md).

## Team and recorded IP/service table

| Mac | Person | Role | Current recorded IPv4 | Service/port |
| --- | --- | --- | --- | --- |
| Mac 1 | Navodit | DNS + client | 10.7.10.22/19 | dnsmasq, UDP/TCP 53 |
| Mac 2 | Sarvesh | Edge / load balancer / TLS | 10.7.22.227/19 | nginx, TCP 80/443 |
| Mac 3 | Trishit | Backend A | 10.7.18.190/19 | Python, TCP 3001 |
| Mac 4 | Husain | Backend B + client | 10.7.24.166/19 | Python, TCP 3002 |

Recorded on the Rishihood Learners network, 28 Sep 2026. Default gateway for all: 10.7.0.1. Recheck every value if the network changes.

### What is already in the first commit on main

These are completed document/source tasks only. Live checks and evidence are separate tasks.

- [x] Team-wide architecture document and shared IP table are in 01_architecture/.
- [x] Topology and request-flow diagrams have editable sources and PNG files in 01_architecture/.
- [x] One shared backend source and its A/B README are in 03_backend_code/. It uses BACKEND_ID and PORT; TEAM is not required.
- [x] Confirm current IP/MAC values and finish the Mac 3 MAC check on the project LAN. Evidence: 04_evidence/A_lan/A-01, A-02, A-03, A-04 match 01_architecture/ip_table.md; A-03 shows Mac 3's active MAC is be:4f:1d:91:b1:8b.
- [x] Run both backend processes and prove Mac 2 can reach both over the LAN. Evidence: 04_evidence/C_backends/C-01, C-04 (running), C-02, C-06 (Mac 2 direct curl).
- [ ] Add DNS, nginx, and TLS setup files to 02_config/. Partial: nginx-teamX.conf, tls_setup_notes.md, teamX-rootCA.crt and mac2-edge-setup.sh are in; dnsmasq-teamX.conf is missing (Navodit).
- [ ] Capture live screenshots, terminal outputs, and Wireshark files under 04_evidence/. Partial: most are saved, including Trishit's H-03a/b/c Mac 3 stop/restore proof and real F-02 DevTools capture. Pending: E-02 (Mac 1 TLS), Mac 1/Mac 4 failover client proof, and wrong DNS server recovery. Two DNS clients are documented under Task B below.
- [ ] Package and rehearse the complete Phase 1 demonstration.

### Completed Mac 4 contributions

- [x] LAN details and pings: `04_evidence/A_lan/A-04_mac4_network_info.png` and `A-08_mac4_ping_all.png`.
- [x] Backend B listener and direct access from Mac 2: `04_evidence/C_backends/C-04_mac4_backendB_running.png` and `C-06_mac2_direct_curl_backendB.png`.
- [x] DNS through Mac 1: `04_evidence/B_dns/B-03_mac4_dig_app.png`.
- [x] Trusted HTTPS client: `04_evidence/E_tls/E-03_mac4_curl_verbose_tls.png`.
- [x] Client load-balancing and browser evidence: `04_evidence/D_loadbalancing/D-04_mac4_xbackend_alternating.png`, `D-05_mac4_browser_backendA.png`, and `D-05_mac4_browser_backendB.png`.

These complete Husain's recorded implementation and evidence tasks. Team gates
below remain separate from one member's completion; demo and viva preparation
remain open until performed.

## Build order and shared gates

Complete Task A first. Tasks B and C can then be built in parallel. Task D/E depends on the DNS and both backends. After the edge works, finish caching, packet capture, and failures. Restore normal settings after every failure demo.

- [x] **A — Private LAN (everyone):** all four Macs on one private network; record interface, IPv4, prefix/mask, gateway, MAC; all 12 directed pings between the Macs succeed. Evidence: 04_evidence/A_lan/. Network info A-01, A-02, A-03, A-04; pings A-05 (Mac 1), A-06 (Mac 2), A-03 (Mac 3), A-08 (Mac 4), all 0% loss.
- [ ] **B — Private DNS (Navodit leads):** Mac 1 answers app.teamX.test and api.teamX.test with Mac 2's IP; at least two other Macs use Mac 1 as resolver. Evidence: dnsmasq-teamX.conf and 04_evidence/B_dns/. Partial: answers proven (B-01, B-02, B-04, B-06). Two clients use Mac 1: Mac 4 (B-03, B-05_mac4, B-06) and Mac 2 (B-05_mac2_dns_server.png, B-08_mac2_resolves_by_name.png). Still missing: dnsmasq-teamX.conf in 02_config/.
- [x] **C — Two backends (Trishit + Husain):** A listens on Mac 3:3001; B on Mac 4:3002; both return JSON and X-Backend; Mac 2 can curl both directly. Evidence: 04_evidence/C_backends/. C-01 (A on *:3001), C-04 (B on *:3002), C-02 and C-06 (Mac 2 direct).
- [x] **D — Edge/load balancing (Sarvesh):** nginx on Mac 2 accepts client traffic and round-robins to both backends. Repeated requests to one hostname show A and B plus upstream address. Evidence: final nginx config, curl output, and edge log. 02_config/nginx-teamX.conf; D-01, D-02 (config, listening); D-03 (edge log alternating); D-04 (Mac 4 by name, B/A/B/A/B/A); D-05 (browser A and B).
- [x] **E — HTTPS/TLS (Sarvesh leads):** certificate covers app.teamX.test; Mac 1 and Mac 4 trust it; HTTPS works by name with no curl -k and no browser warning. Evidence: TLS setup notes and client output under 04_evidence/E_tls/. Certificate and notes (E-01, 02_config/tls_setup_notes.md); Mac 4 (E-03, D-05 browser "Certificate is valid"); Mac 1 (04_evidence/E_tls/E-02_mac1_curl_verbose_tls-2.png, 4 Oct 00:12, verify ok, HTTP/2 200).
- [x] **F — HTTP caching (Trishit):** show Cache-Control and either a browser fresh-cache hit or a conditional request returning 304. Explain the difference. Evidence: 04_evidence/F_caching/. F-01 (200 with max-age=60 and ETag, 304 with no body, no-store on /api/status, through the HTTPS edge). F-02 replaced on 30 Sep with real Chrome DevTools: HTTPS 200 network fetch followed by 200 `(disk cache)`, Disable cache unchecked. Uses an isolated hostname mapping and trusted team CA; it does not prove DNS resolution.
- [x] **G — Complete protocol flow (Husain):** save captures showing client DNS query/answer, TCP SYN/SYN-ACK/ACK, TLS handshake, encrypted data, ports, and matching curl HTTP headers. Evidence: pcapng plus screenshots under 04_evidence/G_protocol_flow/. G_capture1_tls12.pcapng, G_capture2_tls13.pcapng, G-01 to G-08; curl headers in E-03.
- [x] **Phase 1 gate:** from a client, resolve app.teamX.test through Mac 1, reach trusted HTTPS on Mac 2, and receive successful responses from both A and B. Evidence: Mac 4 on 29 Sep: B-03 (Mac 1 answers), E-03 (trusted HTTPS, no -k), D-04 (A and B).

## Required Phase 1 failure demonstrations

For each demo: record the failure, explain the layer, restore the working configuration, and check the normal request again.

- [ ] **Wrong DNS server — Navodit/client:** lookup fails but direct IP reachability remains. Save failure and recovery under 04_evidence/H_failures/. Partial: H-01 shows dig @10.7.10.250 timing out while ping to Mac 2 works; the client resolver was not changed and there is no recovery evidence.
- [x] **Wrong DNS record — Navodit:** lookup returns an incorrect address; show the wrong destination, restore Mac 2's IP, and verify the correct answer. Evidence: H-02_wrong_dns_record.png (answer 10.7.18.190, HTTPS fails) and H-02_wrong_dns_record_restored_mac4.jpeg (10.7.22.227 again). The HTTPS recheck after restore is not shown.
- [x] **Stop Backend A — Trishit + Sarvesh:** requests continue through B; restart A and prove A/B balancing returns. Evidence: H-06 (28 Sep) and 04_evidence/H_failures/H-07_mac2_edge_log_A_stopped_and_restored.png (30 Sep): A/B alternating, A refused and retried on B with every request returning 200, then A/B alternation after restart. Trishit's separate 30 Sep 14:04–14:06 run is saved in H-03a_mac3_both_up.png, H-03b_mac3_A_stopped_all_B.png, and H-03c_mac3_A_restored.png under 04_evidence/H_failures/. These use Mac 3 as client with explicit edge mapping and CA validation; Mac 1/Mac 4 client evidence remains pending.
- [x] **Stop both backends — Sarvesh + backend owners:** edge returns HTTP 502; restart both and confirm normal service. Evidence: 04_evidence/H_failures/H-04_both_backends_down_502.png (Rishihood Learners, 28 Sep 16:41). Both restored 28 Sep 16:44; A/B alternation observed again.
- [x] **Wrong destination port — Husain:** port 8444 refused with SYN and RST/ACK; subsequent HTTPS on 443 returns HTTP/2 200. Evidence: `04_evidence/H_failures/H-05_wrong_port.png` and `H-05_wrong_port.pcapng` (30 Sep, matching curl source port 58336).

## Evidence and submission folder

The PDF says the evaluator should be able to find any evidence within 30 seconds. Keep related items in these folders:

    01_architecture/  topology, IP/service table, request flow, architecture document
    02_config/        dnsmasq, nginx, TLS setup notes, backend launch instructions
    03_backend_code/  server.py, README, helper scripts if any
    04_evidence/A_lan/
    04_evidence/B_dns/
    04_evidence/C_backends/
    04_evidence/D_loadbalancing/
    04_evidence/E_tls/
    04_evidence/F_caching/
    04_evidence/G_protocol_flow/
    04_evidence/H_failures/

Name screenshots by task and content, for example G-03_mac4_tls_clienthello.png. Keep each file in the matching evidence subfolder.

- [ ] Finalize architecture document: four machine roles, IP/service inventory, topology, and request flow showing protocol layers.
- [ ] Save dnsmasq configuration, nginx configuration, TLS certificate setup notes, and backend launch instructions.
- [x] Save complete code for both backends and any helper scripts. Evidence: 03_backend_code/server.py (A and B via BACKEND_ID and PORT), 03_backend_code/README.md, 02_config/mac2-edge-setup.sh.
- [ ] Save DNS, curl/browser headers, Wireshark DNS/TCP/TLS captures, caching proof, and all five failure demonstrations.
- [ ] Check the evidence names, make sure commands and full output are readable, and note any proof that still needs to be captured.
- [ ] Confirm all failures were restored and the live Phase 1 gate still works.

## Section 8 Phase 1 demo order — steps 1–8

- [ ] **1. Topology and inventory — Trishit:** show topology, machine roles, IP table, and service ports.
- [ ] **2. Private LAN — Husain:** show current Mac 4 address and pings; the team can show each Mac's IP/ping proof.
- [ ] **3. DNS — Navodit:** dig app.teamX.test from a client; show Mac 1 as DNS server and Mac 2 as answer.
- [ ] **4. HTTPS — Sarvesh:** open https://app.teamX.test or curl it by name, without warning or -k.
- [ ] **5. Load balancing — Sarvesh:** run repeated curls showing X-Backend A and B and show nginx's upstream log.
- [ ] **6. Packet capture — Husain:** open the saved capture and point out DNS, TCP handshake, TLS handshake, encrypted Application Data, and ports.
- [ ] **7. Caching — Trishit:** show Cache-Control and a browser cache hit or HTTP 304.
- [x] **8. One backend stopped — Trishit:** stop A; show successful responses from B only; restart A. Rehearsed live 30 Sep 13:55 to 13:56 (04_evidence/H_failures/H-07_mac2_edge_log_A_stopped_and_restored.png).

The PDF does not require a video. If the professor requests one separately, confirm length, format, narration/faces, and upload location with them.

If the team must use ports 8080/8443 because ports 80/443 are unavailable, update the nginx config, client URLs, TLS instructions, Wireshark filters, and evidence captions consistently.

## Review 1 marks

| Category | Marks |
| --- | ---: |
| Tasks A + B: LAN and private DNS | 10 |
| Tasks C + D: REST backends, reverse proxy, balancing | 10 |
| Task E: HTTPS/TLS | 8 |
| Task G: packet analysis | 7 |
| Task F: caching and transport understanding | 5 |
| Individual Phase 1 viva | 10 per person |

Each student can earn 50 marks in Review 1: 40 team marks and 10 individual viva marks.

## Questions every person should be ready to answer

- [ ] Trace one request in order: DNS query/answer → TCP handshake → TLS handshake → HTTP request/response → TCP close.
- [ ] Explain why TCP uses SYN, SYN-ACK, ACK and what sequence/ack numbers mean.
- [ ] Identify client ephemeral ports and service ports 53, 443, 3001, and 3002.
- [ ] Explain why Wireshark shows TLS Application Data rather than HTTPS headers, while curl -v can show headers on the client.
- [ ] Explain advertised TCP windows, retransmissions, and how sequence and acknowledgement numbers identify byte positions.
- [ ] Explain what the TLS certificate proves, why clients trust the issuer, and why the demo cannot use curl -k.
- [ ] Explain SNI, TLS 1.2 versus 1.3 certificate visibility, and HTTP/1.1 versus HTTP/2 if nginx negotiates HTTP/2.
- [ ] Explain round robin, Cache-Control max-age, ETag/If-None-Match, HTTP 304, and why stopping one backend can still leave the service available.
