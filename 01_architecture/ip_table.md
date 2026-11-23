# Shared IP/service table

| Mac   | Person  | Role               | Interface | IPv4            | Prefix / mask         | Gateway          | MAC address         | Listening ports |
| ----- | ------- | ------------------ | --------- | --------------- | --------------------- | ---------------- | ------------------- | --------------- |
| Mac 1 | Navodit | DNS + client       | `en0`     | `10.7.4.108`  | `/19 (255.255.224.0)` | `10.7.0.1` | `10:9f:41:bc:ff:5a` | `53 UDP/TCP`    |
| Mac 2 | Sarvesh | Edge / LB / TLS    | `en0`     | `10.7.6.184`  | `/19 (255.255.224.0)` | `10.7.0.1` | `3a:33:4b:89:be:dc` | `80, 443 TCP`   |
| Mac 3 | Trishit | Backend A          | `en0`     | `10.7.18.190`  | `/19 (255.255.224.0)` | `10.7.0.1` | `be:4f:1d:91:b1:8b` | `3001 TCP`      |
| Mac 4 | Husain  | Backend B + client | `en0`     | `10.7.24.166` | `/19 (255.255.224.0)` | `10.7.0.1` | `6e:5a:77:e4:01:0c` | `3002 TCP`      |

Values recorded on the Rishihood Learners network on 28 September 2026.
Mac 1 and Mac 2 rows were rechecked for Phase 2 on 23 November 2026; the Mac 3
and Mac 4 rows still hold the 28 September values until their owners recheck
them. Mac 1's values come from its own `networksetup -getinfo Wi-Fi`,
`route -n get default` and `ipconfig getpacket en0` (`chaddr`).
Mac 2's IPv4, `/19` prefix (`255.255.224.0`), gateway `10.7.0.1` and MAC come
from its own `networksetup -getinfo Wi-Fi`, `route -n get default` and
`ipconfig getpacket en0` (`chaddr`), because newer macOS hides the MAC in
`ifconfig en0`. The Mac 3 and Mac 4 MAC
addresses are the active Wi-Fi addresses seen in Mac 2's ARP table
(`arp -n <IP>`); each owner should confirm theirs with `ifconfig en0`.
Recheck all values if any Mac rejoins or changes network.

On each Mac, capture its row data with:

```sh
date
networksetup -listallhardwareports | grep -A2 "Wi-Fi"
ipconfig getifaddr en0
ifconfig en0 | grep -E "ether|inet "
route -n get default | grep -E "gateway|interface"
networksetup -getinfo Wi-Fi
```
