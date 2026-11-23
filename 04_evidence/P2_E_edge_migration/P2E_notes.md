# P2-E notes: Mac 1 edge cutover screenshots (#16)

Mac 1 (`10.7.4.108`), 23 Nov 2026, IST. Mac 1's Wi-Fi resolvers are
`10.7.4.108` (primary) then `10.7.30.194` (backup, Mac 3). The cutover moved
`app.teamX.test` from Mac 2 (`10.7.6.184`, `mac2-nginx`) to the Mac 4 standby
(`10.7.3.254`, `mac4-standby-nginx`) and back, together with #10 (coordinated
on #45).

## Exact commands

Each screenshot is a fresh Terminal window that ran
`cd ~/Documents/CN && clear && printf '\e[3J' && <command>`, so the command
itself is not on screen. The `<command>` for each shot is below, exactly as
run. No command uses `-k`.

The header filter used in every request loop is:

```sh
grep -iE '^(HTTP|x-backend|x-edge)' | tr -d '\r' | paste -sd ' ' -
```

Written as `<filter>` below.

### P2E-02 (16:39:53)

```sh
date; echo '--- DNS (primary, backup)'
dig +nocmd @10.7.4.108 app.teamX.test +noall +answer
dig +nocmd @10.7.30.194 app.teamX.test +noall +answer
echo '--- Mac 1 system resolver (cache warmed)'
dscacheutil -q host -a name app.teamX.test | grep ip_address
echo '--- Through the edge (no -k)'
for i in $(seq 1 4); do curl -sS -o /dev/null -D - https://app.teamX.test/api/status | <filter>; done
```

### P2E-03 (16:40:00)

```sh
date; echo '--- Cached client: system resolver still holds the old record'
dscacheutil -q host -a name app.teamX.test | grep ip_address
for i in $(seq 1 2); do curl -sS -o /dev/null -D - https://app.teamX.test/api/status | <filter>; done
echo '--- Fresh lookup: both DNS servers already answer Mac 4'
dig +nocmd @10.7.4.108 app.teamX.test +noall +answer
dig +nocmd @10.7.30.194 app.teamX.test +noall +answer
echo '--- Fresh client using that answer (no -k)'
NEW=$(dig +short @10.7.4.108 app.teamX.test)
for i in 1 2; do curl -sS -o /dev/null -D - --resolve app.teamX.test:443:$NEW https://app.teamX.test/api/status | <filter>; done
```

The "fresh client" uses `--resolve` to pin `app.teamX.test` to the address
Mac 1's DNS had just returned (`10.7.3.254`), standing in for a client with
an empty cache. It keeps the hostname, so the certificate is still checked.

### P2E-04a (16:40:25) and P2E-04 (16:41:12)

Same command for both:

```sh
date; echo '--- After TTL expiry: system resolver'
dscacheutil -q host -a name app.teamX.test | grep ip_address
echo '--- 6 requests through the standby edge (no -k)'
for i in $(seq 1 6); do curl -sS -o /dev/null -D - https://app.teamX.test/api/status | <filter>; done
```

### P2E-05 (16:46:13)

```sh
date; echo '--- DNS rolled back (primary, backup)'
dig +nocmd @10.7.4.108 app.teamX.test +noall +answer
dig +nocmd @10.7.30.194 app.teamX.test +noall +answer
echo '--- Mac 1 system resolver'
dscacheutil -q host -a name app.teamX.test | grep ip_address
echo '--- Through the edge (no -k)'
for i in $(seq 1 4); do curl -sS -o /dev/null -D - https://app.teamX.test/api/status | <filter>; done
echo '--- Standby edge stopped'
curl -sS -o /dev/null -m 5 --resolve app.teamX.test:443:10.7.3.254 https://app.teamX.test/api/status
```

### DNS switch on Mac 1

```sh
# 16:39:55, after Mac 4's "switch now" on #45
02_config/phase2/mac1-dns-phase2.sh 10.7.4.108 10.7.3.254 && sudo brew services restart dnsmasq
# 16:45:38, after Mac 4's "switch back now" on #45
02_config/phase2/mac1-dns-phase2.sh 10.7.4.108 10.7.6.184 && sudo brew services restart dnsmasq
```

## Known issues

### P2E-03 heading is wrong

The heading says "both DNS servers already answer Mac 4", but the second
`dig` line (Mac 3, `10.7.30.194`) shows `10.7.6.184`. Mac 3's restart was late:
it answered `10.7.3.254` from 16:42:14 (per Mac 3 on #45). The screenshot is
kept as captured. The cached-versus-fresh comparison comes from Mac 1's
primary, which had switched at 16:39:59.

### First P2E-04 attempt (P2E-04a) still reached Mac 2

`P2E-04a_mac1_1640_still_cached_mac2.png` was taken at 16:40:25, 32 s after
P2E-02's lookup. Mac 1's system resolver still returned `10.7.6.184`, and all
6 requests went through `mac2-nginx`. It was taken out of the evidence folder
at the time and retaken as P2E-04 at 16:41:12; it is committed here as the
original capture.

The old answer has two possible sources, and the screenshot cannot tell them
apart:

- Mac 1's cache had not expired yet (30 s TTL plus a little resolver slack), or
- Mac 1's resolver fell through to Mac 3, which still answered `10.7.6.184`
  until 16:42:14.

By 16:40:36 Mac 1's system resolver returned `10.7.3.254`, while Mac 3 still
returned `10.7.6.184`.

## Other Mac 1 requests in Mac 4's standby log

These are not in any screenshot:

- **16:43:20 to 16:43:21:** a manual recheck. Two requests through Mac 1's
  normal resolver, then one sent straight to the standby with
  `--resolve app.teamX.test:443:10.7.3.254`.
- **16:45:39 to 16:46:07, every 3 s:** a readiness loop waiting to take
  P2E-05. Each check ran
  `curl -s -o /dev/null -w '%{http_code}' -m 3 --resolve app.teamX.test:443:10.7.3.254 https://app.teamX.test/api/status`
  to see whether the standby had stopped. These requests were pinned to the
  standby with `--resolve`, so they did not use Mac 1's resolver and are not a
  TTL effect. The loop stopped when the standby refused connections (16:46:11).
