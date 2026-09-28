# Sarvesh — Mac 2: edge, load balancer, and TLS

**Lead:** Tasks D and E; edge side of Tasks C and G; support the backend failure demonstrations.
**Mac 2 address in the current table:** 10.144.232.67/24 on en0; gateway 10.144.232.191. Recheck it on lab day.

Replace teamX with the assigned team number and use the current backend addresses from 01_architecture/ip_table.md.

**Checklist rule:** tick an item after it works. Write down the evidence file beside the item.

## 1. Join and check the LAN — Task A

- [ ] Join the same private LAN as the other three Macs. Label the terminal and keep the Mac awake during the demo.

    export PS1="[Mac2-Edge-TLS-Sarvesh] %~ %# "
    caffeinate -dims &

- [ ] Record Mac 2's current IP, mask, gateway, interface, and Wi-Fi MAC in the shared IP table.

    date
    networksetup -listallhardwareports | grep -A2 "Wi-Fi"
    ipconfig getifaddr en0
    ifconfig en0 | grep -E "ether|inet "
    route -n get default | grep -E "gateway|interface"
    networksetup -getinfo Wi-Fi

- [ ] Ping Macs 1, 3, and 4. Save a full-window screenshot under 04_evidence/A_lan/.
- [ ] For DNS integration, set Mac 2's Wi-Fi DNS server to Mac 1 and flush the cache.

      sudo networksetup -setdnsservers Wi-Fi 10.144.232.5
      sudo dscacheutil -flushcache
      sudo killall -HUP mDNSResponder
      dig app.teamX.test

## 2. Confirm the backends are reachable — Tasks C and D

- [ ] Ask Trishit and Husain to start their backends, then check both directly from Mac 2. The listener must be reachable on the LAN, and each response must identify its backend.

      date
      curl -i http://<MAC3_IP>:3001/api/status
      curl -i http://<MAC4_IP>:3002/api/status

   Expected: HTTP 200, X-Backend: A from Mac 3, and X-Backend: B from Mac 4. Save the output under 04_evidence/C_backends/.

## 3. Configure nginx as the HTTPS edge and load balancer — Tasks D and E

- [ ] Install nginx and OpenSSL 3 if needed.

      brew install nginx openssl@3

- [ ] Create a server certificate for app.teamX.test. The PDF permits a self-signed certificate. A local CA is another option only with faculty approval. The certificate must contain a Subject Alternative Name for the hostname.

      mkdir -p "$HOME/cn-project/tls"
      openssl req -x509 -newkey rsa:2048 -sha256 -nodes -days 365 \
        -keyout "$HOME/cn-project/tls/app.teamX.test.key" \
        -out "$HOME/cn-project/tls/app.teamX.test.crt" \
        -subj "/CN=app.teamX.test" \
        -addext "subjectAltName=DNS:app.teamX.test,DNS:api.teamX.test"
      chmod 600 "$HOME/cn-project/tls/app.teamX.test.key"
      openssl x509 -in "$HOME/cn-project/tls/app.teamX.test.crt" -noout -subject -issuer -ext subjectAltName

   Keep the private key on Mac 2. Give clients only the public .crt file. Save the certificate creation commands and certificate setup notes in 02_config/.

- [ ] Add an nginx configuration. Put the upstream and server blocks inside the nginx http block. Replace every team name, IP, and certificate path with the current values.

   Define an access log format inside http{} so requests show the selected upstream:

       log_format teamX_lb '$remote_addr [$time_local] "$request" $status -> upstream=$upstream_addr ($upstream_status)';
       access_log logs/teamX_access.log teamX_lb;

      upstream teamX_backends {
          server <MAC3_IP>:3001 max_fails=1 fail_timeout=10s;
          server <MAC4_IP>:3002 max_fails=1 fail_timeout=10s;
      }

      server {
          listen 80;
          server_name app.teamX.test api.teamX.test;
          return 301 https://$host$request_uri;
      }

      server {
          listen 443 ssl;
          server_name app.teamX.test api.teamX.test;
          ssl_certificate     /Users/<MAC2_USER>/cn-project/tls/app.teamX.test.crt;
          ssl_certificate_key /Users/<MAC2_USER>/cn-project/tls/app.teamX.test.key;
          ssl_protocols TLSv1.2 TLSv1.3;

          location / {
              proxy_pass http://teamX_backends;
              proxy_http_version 1.1;
              proxy_set_header Host $host;
              proxy_set_header X-Real-IP $remote_addr;
              proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
              proxy_set_header X-Forwarded-Proto $scheme;
              proxy_connect_timeout 2s;
              proxy_next_upstream error timeout http_502 http_503;
              add_header X-Upstream-Addr $upstream_addr always;
          }
      }

   Nginx's upstream default is round robin. If port 80/443 cannot be used, change to 8080/8443; the PDF permits this. Use those ports consistently in the URLs, firewall rules, evidence, and demo.

- [ ] Test the full nginx configuration, then start or reload nginx. Find the active config path with nginx -T if you are unsure where Homebrew loads it from.

      nginx -t
      sudo nginx
      sudo nginx -s reload

   The config test should say syntax is okay and test is successful. Confirm nginx listens on the selected ports.

- [ ] From a client using Mac 1 DNS, request the service by name.

      date
      curl -i https://app.teamX.test/api/status

   Expected: HTTPS succeeds without -k and the response includes X-Backend and X-Upstream-Addr.

- [ ] Send six separate requests. Confirm that both A and B appear in X-Backend and the upstream address changes between Mac 3:3001 and Mac 4:3002.

      for i in 1 2 3 4 5 6; do
        curl -s -D - -o /dev/null https://app.teamX.test/api/status | grep -iE "^HTTP|x-backend|x-upstream"
      done

   Save full command output under 04_evidence/D_loadbalancing/. Open the URL in a browser and capture one response from A and one from B if browser evidence is requested.

## 4. Help clients trust TLS — Task E

- [ ] Copy the public certificate to Mac 1 and Mac 4. On each client, add it to the System keychain.

      sudo security add-trusted-cert -d -r trustRoot \
        -k /Library/Keychains/System.keychain ~/Downloads/app.teamX.test.crt

- [ ] Ask each client to run curl -v https://app.teamX.test/api/status without -k. It must report successful certificate verification. Save client output under 04_evidence/E_tls/.
- [ ] Explain TLS termination: the client has TLS with nginx; nginx makes a separate plain HTTP connection to the backend.

## 5. Demonstrate backend failures — Task H

- [ ] With Trishit, stop Backend A using Ctrl+C. Send requests through the HTTPS name; nginx should retry Backend B and return success. Capture response headers and nginx log under 04_evidence/H_failures/.
- [ ] Stop both backends. Show that the edge still resolves and completes TLS but returns HTTP 502. Save evidence, then restart both services and verify A/B balancing again.
- [ ] Help Husain demonstrate an unused client destination port and explain the resulting TCP refusal/reset.

## 6. Before the review

- [ ] Put the final nginx config and TLS setup notes in 02_config/.
- [ ] Present demo steps 4 and 5: trusted HTTPS by name, then responses from both backends.
- [ ] Explain round robin, X-Backend, X-Upstream-Addr, TLS trust, TLS termination, and 502.
- [ ] Check off finished items in 06_phase1_checklists/team_overview.md and add evidence paths.
