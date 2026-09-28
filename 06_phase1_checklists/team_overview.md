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
- [ ] Confirm current IP/MAC values and finish the Mac 3 MAC check on the project LAN.
- [ ] Run both backend processes and prove Mac 2 can reach both over the LAN.
- [ ] Add DNS, nginx, and TLS setup files to 02_config/.
- [ ] Capture live screenshots, terminal outputs, and Wireshark files under 04_evidence/.
- [ ] Package and rehearse the complete Phase 1 demonstration.

## Build order and shared gates

Complete Task A first. Tasks B and C can then be built in parallel. Task D/E depends on the DNS and both backends. After the edge works, finish caching, packet capture, and failures. Restore normal settings after every failure demo.

- [ ] **A — Private LAN (everyone):** all four Macs on one private network; record interface, IPv4, prefix/mask, gateway, MAC; all 12 directed pings between the Macs succeed. Evidence: 04_evidence/A_lan/.
- [ ] **B — Private DNS (Navodit leads):** Mac 1 answers app.teamX.test and api.teamX.test with Mac 2's IP; at least two other Macs use Mac 1 as resolver. Evidence: dnsmasq-teamX.conf and 04_evidence/B_dns/.
- [ ] **C — Two backends (Trishit + Husain):** A listens on Mac 3:3001; B on Mac 4:3002; both return JSON and X-Backend; Mac 2 can curl both directly. Evidence: 04_evidence/C_backends/.
- [ ] **D — Edge/load balancing (Sarvesh):** nginx on Mac 2 accepts client traffic and round-robins to both backends. Repeated requests to one hostname show A and B plus upstream address. Evidence: final nginx config, curl output, and edge log.
- [ ] **E — HTTPS/TLS (Sarvesh leads):** certificate covers app.teamX.test; Mac 1 and Mac 4 trust it; HTTPS works by name with no curl -k and no browser warning. Evidence: TLS setup notes and client output under 04_evidence/E_tls/.
- [ ] **F — HTTP caching (Trishit):** show Cache-Control and either a browser fresh-cache hit or a conditional request returning 304. Explain the difference. Evidence: 04_evidence/F_caching/.
- [ ] **G — Complete protocol flow (Husain):** save captures showing client DNS query/answer, TCP SYN/SYN-ACK/ACK, TLS handshake, encrypted data, ports, and matching curl HTTP headers. Evidence: pcapng plus screenshots under 04_evidence/G_protocol_flow/.
- [ ] **Phase 1 gate:** from a client, resolve app.teamX.test through Mac 1, reach trusted HTTPS on Mac 2, and receive successful responses from both A and B.

## Required Phase 1 failure demonstrations

For each demo: record the failure, explain the layer, restore the working configuration, and check the normal request again.

- [ ] **Wrong DNS server — Navodit/client:** lookup fails but direct IP reachability remains. Save failure and recovery under 04_evidence/H_failures/.
- [ ] **Wrong DNS record — Navodit:** lookup returns an incorrect address; show the wrong destination, restore Mac 2's IP, and verify the correct answer.
- [ ] **Stop Backend A — Trishit + Sarvesh:** requests continue through B; restart A and prove A/B balancing returns.
- [x] **Stop both backends — Sarvesh + backend owners:** edge returns HTTP 502; restart both and confirm normal service. Evidence: 04_evidence/H_failures/H-04_both_backends_down_502.png (Rishihood Learners, 28 Sep 16:41). Both restored 28 Sep 16:44; A/B alternation observed again.
- [ ] **Wrong destination port — Husain:** correct host, unused port; show RST/refusal or timeout if filtered, explain IP versus port, restore and recheck 443.

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
- [ ] Save complete code for both backends and any helper scripts.
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
- [ ] **8. One backend stopped — Trishit:** stop A; show successful responses from B only; restart A.

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
