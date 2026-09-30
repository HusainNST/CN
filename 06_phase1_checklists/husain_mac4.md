# Husain — Mac 4: Backend B, client, and Wireshark

**Lead:** Backend B in Task C, client evidence for DNS/load balancing/TLS, complete packet capture in Task G, and the wrong destination port failure.
**Mac 4 address in the current table:** `10.7.24.166/19` on `en0`; gateway `10.7.0.1`.
Current peer addresses: Mac 1 `10.7.10.22`, Mac 2 `10.7.22.227`, Mac 3 `10.7.18.190`.

**Checklist rule:** tick a task after it works and note the proof file. Leave runtime checks open until the live four-Mac system is tested.

## 1. Join and check the LAN — Task A

- [x] Mac 4's IP, prefix, gateway, and MAC are recorded in 01_architecture/architecture_doc.md and 01_architecture/ip_table.md.
- [x] Record the current network details and confirm Mac 4 can ping Macs 1, 2, and 3. Evidence: `04_evidence/A_lan/A-04_mac4_network_info.png` and `04_evidence/A_lan/A-08_mac4_ping_all.png`.
- [x] Retake `A-04_mac4_network_info.png` and `A-08_mac4_ping_all.png` with the required `[Mac4-BackendB-Client-Husain]` prompt visible. Evidence: `04_evidence/A_lan/`.

      export PS1="[Mac4-BackendB-Client-Husain] %~ %# "
      caffeinate -dims &
      date
      networksetup -listallhardwareports | grep -A2 "Wi-Fi"
      ipconfig getifaddr en0
      ifconfig en0 | grep -E "ether|inet "
      route -n get default | grep -E "gateway|interface"
      ping -c 4 10.7.10.22
      ping -c 4 10.7.22.227
      ping -c 4 10.7.18.190

   Save full-window network and ping screenshots in 04_evidence/A_lan/.

## 2. Run Backend B — Task C

- [x] The shared server source supports B with BACKEND_ID=B and PORT=3002.
- [x] Start Backend B from `03_backend_code/`. The listener and successful status response are shown in `04_evidence/C_backends/C-04_mac4_backendB_running.png`.

      BACKEND_ID=B PORT=3002 python3 server.py

- [x] Prove Backend B listens on all interfaces and returns B. Evidence: `04_evidence/C_backends/C-04_mac4_backendB_running.png`.

      date
      lsof -nP -iTCP:3002 -sTCP:LISTEN
      curl -i http://localhost:3002/api/status

   Expected: listener *:3002 or 0.0.0.0:3002, HTTP 200, X-Backend: B. Save under 04_evidence/C_backends/.

- [x] Confirm Mac 2 can curl `http://10.7.24.166:3002/api/status` and receives HTTP 200 with `X-Backend: B`. Evidence: `04_evidence/C_backends/C-06_mac2_direct_curl_backendB.png`.

## 3. Make Mac 4 a test client — Tasks B, D, and E

- [x] Verify DNS queries use Mac 1 and return the edge address. Evidence: `04_evidence/B_dns/B-03_mac4_dig_app.png` (SERVER `10.7.10.22#53`, answer `10.7.22.227`, TTL 60).

      sudo networksetup -setdnsservers Wi-Fi 10.7.10.22
      sudo dscacheutil -flushcache
      sudo killall -HUP mDNSResponder
      date
      dig app.teamX.test

   Expected: SERVER is `10.7.10.22` and the A answer is `10.7.22.227`.

- [x] Trust the public team CA in the System keychain; the certificate validates successfully. Evidence: `04_evidence/E_tls/E-03_mac4_curl_verbose_tls.png`. Never receive or install a private key on the client.

      sudo security add-trusted-cert -d -r trustRoot \
        -k /Library/Keychains/System.keychain ~/Downloads/teamX-rootCA.crt

- [x] Prove TLS and HTTP work by hostname without `-k`. Evidence: `04_evidence/E_tls/E-03_mac4_curl_verbose_tls.png` (certificate verification succeeds; HTTP 200).

      date
      curl -v https://app.teamX.test/api/status

   If verification fails, stop and fix the certificate or trust configuration; do not bypass validation.

- [x] Request `/api/status` six times through the edge. Evidence: `04_evidence/D_loadbalancing/D-04_mac4_xbackend_alternating.png` shows B/A/B/A/B/A.
- [x] Save a full-window browser Backend B screenshot showing the secure connection and valid certificate. Evidence: `04_evidence/D_loadbalancing/D-05_mac4_browser_backendB.png` (30 Sep, backend B, port 3002).
- [x] Save a full-window browser Backend A screenshot with Mac 3 running Backend A. Evidence: `04_evidence/D_loadbalancing/D-05_mac4_browser_backendA.png` (30 Sep, backend A, port 3001, secure connection and valid certificate).
- [x] Retake `B-03_mac4_dig_app.png`, `C-04_mac4_backendB_running.png`, and `D-04_mac4_xbackend_alternating.png` with the required Mac 4 role prompt visible. Evidence: their named files under `04_evidence/`.
- [x] Retake `E-03_mac4_curl_verbose_tls.png` with the required Mac 4 role prompt visible. Evidence: `04_evidence/E_tls/E-03_mac4_curl_verbose_tls.png` (TLS 1.3, certificate subject and issuer, Apple SecTrust verification, HTTP 200).

      for i in 1 2 3 4 5 6; do
        curl -s -D - -o /dev/null https://app.teamX.test/api/status | grep -iE "^HTTP|x-backend|x-upstream"
      done

## 4. Capture a full request in Wireshark — Task G

### Prepare and capture

- [x] Install and use Wireshark with en0 capture permissions. The saved packet captures and packet screenshots confirm capture is working.
- [x] Capture on en0 with Mac 1/Mac 2 in scope before the request; the saved capture includes the DNS lookup and HTTPS flow.

      sudo dscacheutil -flushcache
      sudo killall -HUP mDNSResponder

   Capture filter example: `host 10.7.10.22 or host 10.7.22.227`

- [x] Capture a TLS 1.2 request after DNS, edge, backends, and certificate validation work.

      date
      curl -v --tls-max 1.2 https://app.teamX.test/api/status

- [x] Save the TLS 1.2 capture as `04_evidence/G_protocol_flow/G_capture1_tls12.pcapng`.
- [x] Save the normal TLS 1.3 capture as `04_evidence/G_protocol_flow/G_capture2_tls13.pcapng`.

      sudo dscacheutil -flushcache
      sudo killall -HUP mDNSResponder
      curl -v https://app.teamX.test/api/status

### Inspect and screenshot the packets

Open the saved capture. Use these display filters one at a time. Select packets and expand the matching fields in Packet Details.

- [x] DNS: query and response with Mac 4 querying Mac 1 and the A record for Mac 2. Evidence: `G-01_mac4_dns_query_response.png`.
- [x] TCP: SYN, SYN-ACK, ACK with sequence/acknowledgement numbers and ephemeral source port visible. Evidence: `G-02_mac4_tcp_handshake.png`.
- [x] TLS ClientHello: SNI `app.teamX.test` and ALPN visible. Evidence: `G-03_mac4_tls_clienthello.png`.
- [x] ServerHello/certificate screenshot shows the certificate subject and issuer. Evidence: `G-04_mac4_tls_serverhello_certificate.png`.
- [x] ChangeCipherSpec and encrypted handshake message visible. Evidence: `G-05_mac4_changecipherspec.png`.
- [x] Application Data records visible as encrypted data. Evidence: `G-06_mac4_application_data_encrypted.png`.
- [x] Compare curl output with the encrypted records. Evidence: `04_evidence/E_tls/E-03_mac4_curl_verbose_tls.png` and `G-06_mac4_application_data_encrypted.png`.
- [x] Show the UDP and TCP Conversations and identify the client ephemeral ports and destination ports 53/UDP and 443/TCP. Evidence: the two `G-08` screenshots below.
- [x] Flow Graph shows DNS, TCP setup, TLS, and Application Data. Evidence: `G-07_mac4_flow_graph.png`.
- [x] Show UDP and TCP conversations with ephemeral client ports to destination 53/UDP and 443/TCP. Evidence: `G-08_mac4_udp_conversation.png` and `G-08_mac4_tcp_conversation.png`.
- [x] Save the packet screenshots and both `.pcapng` files under `04_evidence/G_protocol_flow/`.

## 5. Demonstrate the wrong destination port — Task H

- [x] Capture a wrong destination port attempt on en0; normal port 443 works and port 8444 is refused. Evidence: `04_evidence/H_failures/H-05_wrong_port.png` and `H-05_wrong_port.pcapng`.
- [x] Save terminal output and Wireshark packets from the same run. Evidence: `04_evidence/H_failures/H-05_wrong_port.png` and `H-05_wrong_port.pcapng` (30 Sep, curl source port 58336 matches the captured SYN and RST/ACK).

      date
      ping -c 2 app.teamX.test
      nc -vz app.teamX.test 443

- [x] Try unused port 8444 and capture the refusal. Evidence: `H-05_wrong_port.png` and `H-05_wrong_port.pcapng`.

      nc -vz app.teamX.test 8444
      curl -v https://app.teamX.test:8444/

- [x] In Wireshark filter `tcp.port == 8444`; show the client's SYN and Mac 2's RST, ACK. Evidence: `H-05_wrong_port.png` and `H-05_wrong_port.pcapng`.
- [x] Save the terminal and RST/ACK evidence under `04_evidence/H_failures/`.
- [x] After the wrong-port attempt, recheck HTTPS on port 443. Evidence: `04_evidence/H_failures/H-05_wrong_port.png` shows `curl -i https://app.teamX.test/api/status` returning HTTP/2 200 after the refusal.

## 6. Before the review

- [ ] Present demo steps 2 and 6: LAN checks, then the saved capture with DNS/TCP/TLS/ports.
- [ ] Explain ephemeral versus service ports, TCP sequence/acknowledgement numbers, the three-way handshake, TLS 1.2 versus 1.3, and why HTTPS headers are encrypted in the capture.
- [x] Update `06_phase1_checklists/team_overview.md` with completed Mac 4 contributions, Task G, the wrong-port demonstration, and evidence paths.
