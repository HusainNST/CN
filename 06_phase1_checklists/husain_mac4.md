# Husain — Mac 4: Backend B, client, and Wireshark

**Lead:** Backend B in Task C, client evidence for DNS/load balancing/TLS, complete packet capture in Task G, and the wrong destination port failure.
**Mac 4 address in the current table:** 10.144.232.15/24 on en0; gateway 10.144.232.191. Recheck on lab day.

**Checklist rule:** tick a task after it works and note the proof file. Leave runtime checks open until the live four-Mac system is tested.

## 1. Join and check the LAN — Task A

- [x] Mac 4's IP, prefix, gateway, and MAC are recorded in 01_architecture/architecture_doc.md and 01_architecture/ip_table.md.
- [ ] Recheck current network details, label the terminal, keep the Mac awake, and ping Macs 1, 2, and 3.

      export PS1="[Mac4-BackendB-Client-Husain] %~ %# "
      caffeinate -dims &
      date
      networksetup -listallhardwareports | grep -A2 "Wi-Fi"
      ipconfig getifaddr en0
      ifconfig en0 | grep -E "ether|inet "
      route -n get default | grep -E "gateway|interface"
      ping -c 4 <MAC1_IP>
      ping -c 4 <MAC2_IP>
      ping -c 4 <MAC3_IP>

   Save full-window network and ping screenshots in 04_evidence/A_lan/.

## 2. Run Backend B — Task C

- [x] The shared server source supports B with BACKEND_ID=B and PORT=3002.
- [ ] From 03_backend_code/, start B and leave the server terminal open.

      BACKEND_ID=B PORT=3002 python3 server.py

- [ ] In a second terminal, prove it listens on all interfaces and returns B.

      date
      lsof -nP -iTCP:3002 -sTCP:LISTEN
      curl -i http://localhost:3002/api/status

   Expected: listener *:3002 or 0.0.0.0:3002, HTTP 200, X-Backend: B. Save under 04_evidence/C_backends/.

- [ ] Ask Sarvesh to curl http://<MAC4_IP>:3002/api/status from Mac 2. Confirm X-Backend: B and save the output under 04_evidence/C_backends/.

## 3. Make Mac 4 a test client — Tasks B, D, and E

- [ ] Set Wi-Fi DNS to Mac 1, flush the local cache, and verify the response server and answer.

      sudo networksetup -setdnsservers Wi-Fi 10.144.232.5
      sudo dscacheutil -flushcache
      sudo killall -HUP mDNSResponder
      date
      dig app.teamX.test

   Expected: SERVER is 10.144.232.5 and the A answer is 10.144.232.67. Save under 04_evidence/B_dns/.
- [ ] If Chrome resolves outside the team DNS, turn off Chrome's Use secure DNS for the demo. Turn off iCloud Private Relay if it diverts project traffic.

- [ ] Receive the public certificate from Sarvesh and trust it in the System keychain. Never receive or install a private key on the client.

      sudo security add-trusted-cert -d -r trustRoot \
        -k /Library/Keychains/System.keychain ~/Downloads/app.teamX.test.crt

- [ ] Prove TLS and HTTP work by hostname without -k. Keep curl -v output visible and save it under 04_evidence/E_tls/.

      date
      curl -v https://app.teamX.test/api/status

   If verification fails, stop and fix the certificate or trust configuration; do not bypass validation.

- [ ] Request /api/status six times through the edge. Confirm X-Backend alternates between A and B; save the complete output under 04_evidence/D_loadbalancing/.

      for i in 1 2 3 4 5 6; do
        curl -s -D - -o /dev/null https://app.teamX.test/api/status | grep -iE "^HTTP|x-backend|x-upstream"
      done

## 4. Capture a full request in Wireshark — Task G

### Prepare and capture

- [ ] Install Wireshark and its macOS capture permissions (Install ChmodBPF from the official Wireshark disk image). Open Wireshark and confirm en0 shows traffic.
- [ ] Close browsers/chat apps, flush the DNS cache, choose en0, and set a capture filter for Mac 1 or Mac 2. Start capturing before curl so the DNS lookup is included.

      sudo dscacheutil -flushcache
      sudo killall -HUP mDNSResponder

   Capture filter example: host 10.144.232.5 or host 10.144.232.67

- [ ] With both backends, DNS, nginx, and client certificate trust working, make one TLS 1.2 request and stop the capture.

      date
      curl -v --tls-max 1.2 https://app.teamX.test/api/status

- [ ] Save as 04_evidence/G_protocol_flow/G_capture1_tls12.pcapng.
- [ ] Repeat with a normal curl request, save as G_capture2_tls13.pcapng. Confirm curl negotiated TLS 1.3; if it chose 1.2, record the actual version instead.

      sudo dscacheutil -flushcache
      sudo killall -HUP mDNSResponder
      curl -v https://app.teamX.test/api/status

### Inspect and screenshot the packets

Open the saved capture. Use these display filters one at a time. Select packets and expand the matching fields in Packet Details.

- [ ] DNS: filter dns.qry.name matches "(?i)app.teamX.test". Show Mac 4's query to Mac 1 port 53, then the response A record for Mac 2. An AAAA query with no answer is normal.
- [ ] TCP: filter tcp.port == 443 && tcp.flags.syn == 1. Show SYN, SYN-ACK, ACK and the client's ephemeral source port. Select the first packet and use its stream number for tcp.stream eq N.
- [ ] TLS: filter tls.handshake. In ClientHello, show SNI app.teamX.test and ALPN if present. Show ServerHello and negotiated version/cipher. The TLS 1.2 capture can show Certificate details in clear text; TLS 1.3 encrypts Certificate after ServerHello.
- [ ] ChangeCipherSpec: filter tls.record.content_type == 20. Explain TLS 1.3 may show a compatibility ChangeCipherSpec.
- [ ] Encrypted data: filter tls.record.content_type == 23. Show Application Data records; the HTTP payload is ciphertext.
- [ ] Compare Wireshark with curl -v. Curl displays HTTP headers at the client before encryption; Wireshark sees encrypted records.
- [ ] Show ports using Statistics → Conversations for UDP and TCP. Point out the high client ephemeral ports and destination 53/UDP and 443/TCP.
- [ ] Show Statistics → Flow Graph with “Limit to display filter” selected and filter dns || tcp.port == 443. It should show DNS, TCP setup, TLS, and data in order.
- [ ] Save full-window screenshots in 04_evidence/G_protocol_flow/: DNS query/response, TCP handshake, ClientHello, ServerHello/certificate, ChangeCipherSpec, Application Data, Flow Graph, and Conversations. Save the .pcapng files too.

## 5. Demonstrate the wrong destination port — Task H

- [ ] Start a Wireshark capture on en0 with filter host 10.144.232.67. Confirm DNS and the normal service still work.

      date
      ping -c 2 app.teamX.test
      nc -vz app.teamX.test 443

- [ ] Try an unused port, such as 8444, and capture the result.

      nc -vz app.teamX.test 8444
      curl -v https://app.teamX.test:8444/

- [ ] In Wireshark filter tcp.port == 8444. If the port is closed, show the client's SYN and Mac 2's RST, ACK. A filtered port may time out instead; explain the packets actually seen.
- [ ] Save the full terminal screenshot and packet evidence under 04_evidence/H_failures/H-05_wrong_port.png.
- [ ] Restore and recheck HTTPS on port 443.

## 6. Before the review

- [ ] Present demo steps 2 and 6: LAN checks, then the saved capture with DNS/TCP/TLS/ports.
- [ ] Explain ephemeral versus service ports, TCP sequence/acknowledgement numbers, the three-way handshake, TLS 1.2 versus 1.3, and why HTTPS headers are encrypted in the capture.
- [ ] Check off finished items in 06_phase1_checklists/team_overview.md and add evidence paths.
