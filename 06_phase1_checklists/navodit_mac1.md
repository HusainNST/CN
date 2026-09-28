# Navodit — Mac 1: private DNS and client

**Lead:** Task B (DNS) and the two DNS failure demonstrations.
**Mac 1 address in the current table:** 10.7.10.22/19 on en0; gateway 10.7.0.1. Recheck it on lab day.

This file is a do-it-yourself Phase 1 guide. Replace teamX with the team number, and replace any IP placeholder if the shared table changes.

**Checklist rule:** tick an item after the check succeeds. Add the screenshot or file path after the item so the next person can verify it.

## 1. Join and check the LAN — Task A

- [ ] Put Mac 1 and Macs 2, 3, and 4 on the same private Wi-Fi/LAN. Turn off VPN or Private Relay if they interfere. Keep Wi-Fi address mode fixed for the lab.
- [ ] If pings or incoming service connections fail, check client isolation on the router and macOS Firewall permissions before debugging DNS.
- [ ] Label the terminal and keep the Mac awake during the demo.

    export PS1="[Mac1-DNS-Client-Navodit] %~ %# "
    caffeinate -dims &

- [ ] Record the current network details. Confirm the interface is en0 and write the IPv4, mask, gateway, and Wi-Fi MAC in 01_architecture/ip_table.md.

    date
    networksetup -listallhardwareports | grep -A2 "Wi-Fi"
    ipconfig getifaddr en0
    ifconfig en0 | grep -E "ether|inet "
    route -n get default | grep -E "gateway|interface"
    networksetup -getinfo Wi-Fi

- [ ] Ping each other Mac. All four Macs together should complete 12 directed ping checks.

    ping -c 4 <MAC2_IP>
    ping -c 4 <MAC3_IP>
    ping -c 4 <MAC4_IP>

- [ ] Save a full-window terminal screenshot in 04_evidence/A_lan/ showing date, prompt, network output, or pings. Example names: A-01_mac1_network_info.png and A-05_mac1_ping_all.png.

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

- [ ] Check the config syntax. If port 53 is already in use, identify the process before changing anything.

      sudo "$(brew --prefix)/sbin/dnsmasq" --test --conf-file=02_config/dnsmasq-teamX.conf
      sudo lsof -nP -iUDP:53 -iTCP:53

- [ ] Start dnsmasq in the foreground and leave this terminal open during the demo. A successful foreground start stays running without a fatal error.

      sudo "$(brew --prefix)/sbin/dnsmasq" --keep-in-foreground --conf-file=02_config/dnsmasq-teamX.conf

- [ ] From another Mac, point Wi-Fi DNS to Mac 1. Do this on at least two client Macs; each owner should save their own proof.

      sudo networksetup -setdnsservers Wi-Fi 10.7.10.22
      sudo dscacheutil -flushcache
      sudo killall -HUP mDNSResponder

- [ ] From Mac 4 and one other client, check both names. The answer should be Mac 2 and the SERVER line should identify Mac 1.

      date
      dig app.teamX.test
      dig api.teamX.test

   Save full terminal screenshots under 04_evidence/B_dns/. The Phase 1 proof should show the query name, answer address, and DNS server address.

- [ ] Open the service by name, for example https://app.teamX.test/api/status. Do not type Mac 2's IP into the final HTTPS URL.

## 3. Demonstrate the DNS failures — Task H

### Wrong DNS server on a client

- [ ] On a client, temporarily configure an unreachable DNS address, then show that the name lookup fails while direct IP connectivity to Mac 2 still works.

      sudo networksetup -setdnsservers Wi-Fi 192.0.2.53
      sudo dscacheutil -flushcache
      sudo killall -HUP mDNSResponder
      date
      dig app.teamX.test
      ping -c 2 10.7.22.227

- [ ] Restore Mac 1 as that client's resolver and prove lookup works again.

      sudo networksetup -setdnsservers Wi-Fi 10.7.10.22
      sudo dscacheutil -flushcache
      sudo killall -HUP mDNSResponder
      dig app.teamX.test

   Save the failed lookup and restored lookup under 04_evidence/H_failures/.

### DNS record points to a wrong IP

- [ ] Temporarily change the app.teamX.test address line in dnsmasq-teamX.conf to 192.0.2.123. Restart the foreground dnsmasq process with the edited file and flush the client's DNS cache.
- [ ] Run dig app.teamX.test and show that DNS returns the wrong address. Try the request and record the observed result. Restore the correct Mac 2 address immediately afterward.
- [ ] Restart dnsmasq with the restored file, flush the client cache, and confirm the correct answer and HTTPS service work again.
- [ ] Save evidence of the wrong answer and restored answer under 04_evidence/H_failures/.

## 4. Before the review

- [ ] Put the final dnsmasq configuration and a short start/stop note in 02_config/.
- [ ] Present demo step 3: dig from a client, with Mac 1 shown as the server and Mac 2 shown in the answer.
- [ ] Be able to explain that DNS finds an IP address; TCP then connects to a port on that address.
- [ ] Explain the A record, UDP/TCP port 53, why the project uses .test, and what changes in each DNS failure.
- [ ] Check off the matching tasks in 06_phase1_checklists/team_overview.md and add evidence paths.
