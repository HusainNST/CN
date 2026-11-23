# Final demo: Mac 2 edge (steps 4, 5, 7, 8)

Mac 2 (`10.7.6.184`) is the primary HTTPS edge for `app.teamX.test` and
`api.teamX.test`. It load balances Backend A (`10.7.30.194:3001`) and Backend B
(`10.7.3.254:3002`) and terminates TLS with the certificate signed by
`teamX-rootCA`. The evidence for each step is listed in
[`04_evidence/README.md`](../04_evidence/README.md); this file is what to run
live.

## Before the demo, on Mac 2

```sh
ipconfig getifaddr en0       # must be 10.7.6.184, or every IP table and DNS record is stale
cd "<repo>"
sudo nginx -t
pgrep -lf 'nginx: master' || sudo nginx      # nginx does not restart after sleep or reboot
curl -s -o /dev/null -w '%{http_code}\n' http://10.7.30.194:3001/api/status   # Backend A: 200
curl -s -o /dev/null -w '%{http_code}\n' http://10.7.3.254:3002/api/status    # Backend B: 200
```

If a backend IP has changed, run
`02_config/phase2/mac2-edge-phase2.sh <MAC3_IP> <MAC4_IP>` and then
`sudo nginx -t && sudo nginx -s reload`.

## Live commands

Run from a client whose DNS is Mac 1 then Mac 3. On Mac 2 itself, or if DNS is
not live yet, add `--resolve app.teamX.test:443:10.7.6.184`; it keeps the
hostname, so the certificate is still checked. Never use `-k`.

**Step 4, trusted HTTPS by name**

```sh
curl -sv https://app.teamX.test/api/status -o /dev/null 2>&1 | grep -E 'SSL connection|ALPN|issuer|HTTP/2'
openssl s_client -connect app.teamX.test:443 -servername app.teamX.test -CAfile 02_config/teamX-rootCA.crt </dev/null 2>/dev/null | grep -E 'issuer=|Verify return'
```

Expect issuer `teamX Local Root CA` and `Verify return code: 0 (ok)`.

**Step 5, load balancing**

```sh
for i in 1 2 3 4 5 6; do curl -s -o /dev/null -D - https://app.teamX.test/api/status | grep -iE '^x-(backend|upstream-addr)' | tr -d '\r' | paste -sd' ' -; done
```

Expect A and B alternating. On Mac 2, show the same in
`tail -f /opt/homebrew/var/log/nginx/teamX_access.log`.

**Step 7, caching and a 304**

```sh
curl -sI https://app.teamX.test/api/cached | grep -iE '^(HTTP|cache-control|etag)'
ETAG=$(curl -sI https://app.teamX.test/api/cached | tr -d '\r' | awk -F': ' 'tolower($1)=="etag"{print $2}')
curl -s -o /dev/null -D - -H "If-None-Match: $ETAG" https://app.teamX.test/api/cached | head -1
```

Expect `cache-control: public, max-age=60`, an `etag`, then `HTTP/2 304`.
Checked through Mac 2 on 23 Nov 2026 at 17:27 IST.

**Step 8, one backend fails**

Keep the step 5 loop and Mac 2's access log running while Mac 3 stops
Backend A. Every request should still return `200` from B. When nginx retries,
the log shows `upstream=10.7.30.194:3001, 10.7.3.254:3002 (502, 200)`. About
10 s after A restarts (`fail_timeout`), A is back in rotation.

Change one thing at a time. Our only client-visible errors came from stopping
a backend while a `pf` rule was being loaded on the other one
(`04_evidence/P2_D_ha_failover/P2D_note_502_burst.md`).

## Points to explain at the viva

- **TLS trust:** Mac 2 created `teamX-rootCA` and signed the edge certificate
  (SANs `app` and `api.teamX.test`), and later Mac 4's standby certificate from
  its CSR. No private key left its Mac.
- **Failover:** `max_fails=1 fail_timeout=10s` marks a backend down after one
  failure, and `proxy_next_upstream` retries the same request on the other
  backend, so the client still gets `200`. One transient error can take a
  healthy backend out for 10 s.
- **Caching:** `Cache-Control: public, max-age=60` plus an `ETag`; a request
  with `If-None-Match` gets `304 Not Modified` and no body.
- **Single point of failure:** Mac 2's nginx. Options to remove it are in
  `04_evidence/P2_D_ha_failover/spof_analysis.md`.
