# Navodit — Mac 1: private DNS and client

**Lead:** Task B (DNS) and the two DNS failure demonstrations.
**Mac 1 address in the current table:** 10.7.10.22/19 on en0; gateway 10.7.0.1. Recheck it on lab day.

This file is a do-it-yourself Phase 1 guide. Replace teamX with the team number, and replace any IP placeholder if the shared table changes.

**Checklist rule:** tick an item after the check succeeds. Add the screenshot or file path after the item so the next person can verify it.

## 1. Join and check the LAN — Task A

- [x] Put Mac 1 and Macs 2, 3, and 4 on the same private Wi-Fi/LAN. Turn off VPN or Private Relay if they interfere. Keep Wi-Fi address mode fixed for the lab. Evidence: `04_evidence/A_lan/A-01_mac1_network_info.png` (10.7.10.22/19, gateway 10.7.0.1, 28 Sep 16:40) and `A-05_mac1_ping_all.png`.
- [ ] If pings or incoming service connections fail, check client isolation on the router and macOS Firewall permissions before debugging DNS.
- [x] Label the terminal and keep the Mac awake during the demo. Evidence: `[Mac1-DNS-Navodit]` prompt visible in every Mac 1 screenshot. `caffeinate` is not shown; run it on demo day.

    export PS1="[Mac1-DNS-Client-Navodit] %~ %# "
    caffeinate -dims &

- [x] Record the current network details. Confirm the interface is en0 and write the IPv4, mask, gateway, and Wi-Fi MAC in 01_architecture/ip_table.md. Evidence: `A-01_mac1_network_info.png` (en0, 10.7.10.22, 0xffffe000, gateway 10.7.0.1, ether 10:9f:41:bc:ff:5a); values match `01_architecture/ip_table.md`.

    date
    networksetup -listallhardwareports | grep -A2 "Wi-Fi"
    ipconfig getifaddr en0
    ifconfig en0 | grep -E "ether|inet "
    route -n get default | grep -E "gateway|interface"
    networksetup -getinfo Wi-Fi

- [x] Ping each other Mac. All four Macs together should complete 12 directed ping checks. Evidence: `A-05_mac1_ping_all.png` (0% loss to 10.7.22.227, 10.7.18.190, 10.7.24.166; 28 Sep 16:43). The other nine checks are in A-03, A-06 and A-08.

    ping -c 4 <MAC2_IP>
    ping -c 4 <MAC3_IP>
    ping -c 4 <MAC4_IP>

- [x] Save a full-window terminal screenshot in 04_evidence/A_lan/ showing date, prompt, network output, or pings. Example names: A-01_mac1_network_info.png and A-05_mac1_ping_all.png. Evidence: both files exist with date and prompt visible.

## 2. Run the private DNS server — Task B

1. Install dnsmasq if it is not already installed:

       brew install dnsmasq

2. Run the remaining commands from the project root, so the relative config path below resolves.

3. Create 02_config/dnsmasq-teamX.conf. Use the current IPs from the shared table:

       port=53
       listen-address=127.0.0.1,10.7.10.22
       bind-interfaces
       domain-needed
       bogus-priv
       local-ttl=60
       address=/app.teamX.test/10.7.22.227
       address=/api.teamX.test/10.7.22.227

   Change teamX to your team number. Change 10.7.10.22 if Mac 1's address changes. Both names must point to Mac 2, not to a backend.

- [x] Check the config syntax. If port 53 is already in use, identify the process before changing anything. Evidence: `04_evidence/B_dns/B-02_mac1_dnsmasq_running.png` ("syntax check OK", 28 Sep 16:48). The config tested was `/opt/homebrew/etc/dnsmasq.d/teamX.conf` (shown in `B-01_mac1_dnsmasq_conf.png`), not `02_config/dnsmasq-teamX.conf`.

      sudo "$(brew --prefix)/sbin/dnsmasq" --test --conf-file=02_config/dnsmasq-teamX.conf
      sudo lsof -nP -iUDP:53 -iTCP:53

- [x] Start dnsmasq in the foreground and leave this terminal open during the demo. A successful foreground start stays running without a fatal error. Evidence: `B-02_mac1_dnsmasq_running.png` shows dnsmasq running as a `brew services` daemon instead of in the foreground, listening on UDP and TCP 53 at 10.7.10.22 and 127.0.0.1.

      sudo "$(brew --prefix)/sbin/dnsmasq" --keep-in-foreground --conf-file=02_config/dnsmasq-teamX.conf

- [x] From another Mac, point Wi-Fi DNS to Mac 1. Do this on at least two client Macs; each owner should save their own proof. Evidence: Mac 4 (`B-05_mac4_dns_server.jpeg`, `B-03_mac4_dig_app.png`, queries from 10.7.24.166 in `B-06_mac1_query_log.png`) and Mac 2 (`B-05_mac2_dns_server.png`, `B-08_mac2_resolves_by_name.png`, 30 Sep 12:14). `B-05_clients_dns_settings.png` shows Mac 1's own resolver set to 10.144.232.5, an old network address, so it does not count.

      sudo networksetup -setdnsservers Wi-Fi 10.7.10.22
      sudo dscacheutil -flushcache
      sudo killall -HUP mDNSResponder

- [ ] From Mac 4 and one other client, check both names. The answer should be Mac 2 and the SERVER line should identify Mac 1.

      date
      dig app.teamX.test
      dig api.teamX.test

   Save full terminal screenshots under 04_evidence/B_dns/. The Phase 1 proof should show the query name, answer address, and DNS server address.

   Pending: Mac 4 (`B-03_mac4_dig_app.png`) and Mac 2 (`B-08_mac2_resolves_by_name.png`) show `app` by default resolver. Neither client has saved `dig` output for `api`. `B-04_mac1_dig_api_and_nslookup.png` runs on Mac 1 itself, so it is not a client check.

- [x] Open the service by name, for example https://app.teamX.test/api/status. Do not type Mac 2's IP into the final HTTPS URL. Evidence: 04_evidence/E_tls/E-02_mac1_curl_verbose_tls-2.png (4 Oct 00:12: dig SERVER 10.7.10.22, curl by name HTTP/2 200, certificate verified).

## 3. Demonstrate the DNS failures — Task H

### Wrong DNS server on a client

- [ ] On a client, temporarily configure an unreachable DNS address, then show that the name lookup fails while direct IP connectivity to Mac 2 still works.

      sudo networksetup -setdnsservers Wi-Fi 192.0.2.53
      sudo dscacheutil -flushcache
      sudo killall -HUP mDNSResponder
      date
      dig app.teamX.test
      ping -c 2 10.7.22.227

   Partial: `04_evidence/H_failures/H-01_wrong_dns_server.png` (28 Sep 16:56) shows `dig @10.7.10.250` timing out while `ping 10.7.22.227` works. The client resolver setting was never changed, so this shows the idea but not the configured failure.

- [ ] Restore Mac 1 as that client's resolver and prove lookup works again. Pending: no restore evidence for this failure.

      sudo networksetup -setdnsservers Wi-Fi 10.7.10.22
      sudo dscacheutil -flushcache
      sudo killall -HUP mDNSResponder
      dig app.teamX.test

   Save the failed lookup and restored lookup under 04_evidence/H_failures/.

### DNS record points to a wrong IP

- [x] Temporarily change the app.teamX.test address line in dnsmasq-teamX.conf to 192.0.2.123. Restart the foreground dnsmasq process with the edited file and flush the client's DNS cache. Evidence: `H-02_wrong_dns_record.png` (28 Sep 16:58). The record was changed to 10.7.18.190 (Mac 3) instead of 192.0.2.123, and dnsmasq was restarted with `brew services`.
- [x] Run dig app.teamX.test and show that DNS returns the wrong address. Try the request and record the observed result. Restore the correct Mac 2 address immediately afterward. Evidence: `H-02_wrong_dns_record.png` (answer 10.7.18.190, HTTPS "connection failed"). The curl used `--resolve` and `-s`, so it did not use the DNS answer and hid the error reason.
- [ ] Restart dnsmasq with the restored file, flush the client cache, and confirm the correct answer and HTTPS service work again. Partial: `H-02_wrong_dns_record_restored_mac4.jpeg` shows Mac 4 getting 10.7.22.227 again (28 Sep 17:00). The config restore, the restart and the HTTPS recheck are not shown.
- [x] Save evidence of the wrong answer and restored answer under 04_evidence/H_failures/. Evidence: `H-02_wrong_dns_record.png` and `H-02_wrong_dns_record_restored_mac4.jpeg`.

## 4. Before the review

- [ ] Put the final dnsmasq configuration and a short start/stop note in 02_config/. Partial: `02_config/dnsmasq-teamX.conf` was added 4 Oct, but it is the template, not the running config shown in `B-01_mac1_dnsmasq_conf.png` (missing `local=/teamX.test/`, `no-resolv`, `server=` forwarders and `log-queries`; uses `address=` instead of `host-record=`). Replace it with `/opt/homebrew/etc/dnsmasq.d/teamX.conf` and add a start/stop note.
- [ ] Present demo step 3: dig from a client, with Mac 1 shown as the server and Mac 2 shown in the answer.
- [ ] Be able to explain that DNS finds an IP address; TCP then connects to a port on that address.
- [ ] Explain the A record, UDP/TCP port 53, why the project uses .test, and what changes in each DNS failure.
- [ ] Check off the matching tasks in 06_phase1_checklists/team_overview.md and add evidence paths.
