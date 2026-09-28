# Shared IP/service table

| Mac   | Person  | Role               | Interface | IPv4            | Prefix / mask         | Gateway          | MAC address         | Listening ports |
| ----- | ------- | ------------------ | --------- | --------------- | --------------------- | ---------------- | ------------------- | --------------- |
| Mac 1 | Navodit | DNS + client       | `en0`     | `10.144.232.5`  | `/24 (255.255.255.0)` | `10.144.232.191` | `10:9f:41:bc:ff:5a` | `53 UDP/TCP`    |
| Mac 2 | Sarvesh | Edge / LB / TLS    | `en0`     | `10.144.232.67` | `/24 (255.255.255.0)` | `10.144.232.191` | `7a:62:d1:c7:63:6c` | `80, 443 TCP`   |
| Mac 3 | Trishit | Backend A          | `en0`     | `10.144.232.1`  | `/24 (255.255.255.0)` | `10.144.232.191` | `3e:1b:0f:b0:84:64` | `3001 TCP`      |
| Mac 4 | Husain  | Backend B + client | `en0`     | `10.144.232.15` | `/24 (255.255.255.0)` | `10.144.232.191` | `92:f0:37:09:fa:53` | `3002 TCP`      |

Mac 3's values come from Trishit's `en0` output on 28 September 2026: IPv4
`10.144.232.1`, prefix `/24` (`255.255.255.0`), and gateway `10.144.232.191`.
`ifconfig en0` reports MAC `3e:1b:0f:b0:84:64`; this matches the LAN neighbor
entry for `10.144.232.1`. The same output lists `10:9f:41:c1:7f:a5` as the
Wi-Fi Ethernet Address / Wi-Fi ID, so verify which MAC should be recorded
before final submission. All addresses should be rechecked on the project
LAN, since DHCP or the selected Wi-Fi network can change them. Mac 1's values
are still pending.

On each Mac, capture its row data with:

```sh
date
networksetup -listallhardwareports | grep -A2 "Wi-Fi"
ipconfig getifaddr en0
ifconfig en0 | grep -E "ether|inet "
route -n get default | grep -E "gateway|interface"
networksetup -getinfo Wi-Fi
```
