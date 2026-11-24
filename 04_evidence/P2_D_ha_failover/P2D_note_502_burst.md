# P2-D note: brief 502 burst at 15:56 IST, 23 Nov 2026

During the Extension D drill, Mac 1 briefly saw `HTTP/2 502` from the edge.
It is not in any screenshot. This note records it.

## What Mac 1 saw

Mac 1 (`10.7.4.108`) polling `https://app.teamX.test/api/status`:

| Time (IST) | Result |
| --- | --- |
| 15:56:07 | 1 × `HTTP/2 200` (`x-backend: B`), then 5 × `HTTP/2 502` |
| 15:56:19 onward | Every request `HTTP/2 200`, `x-backend: B` |

## What Mac 2's edge logged

From Mac 2's `teamX_access.log`, as quoted by Mac 2 in the #43 review:

```
10.7.4.108 [23/Nov/2026:15:56:08] ... 502 -> upstream=10.7.3.254:3002, teamX_backends (502, 502)
10.7.4.108 [23/Nov/2026:15:56:08] ... 502 -> upstream=teamX_backends (502)   x3
10.7.4.108 [23/Nov/2026:15:56:09] ... 502 -> upstream=teamX_backends (502)
```

## Cause

At about 15:56:08 Mac 4's pf went from disabled to enabled (`P2C-02` in #42).
The isolate script's saved pf state file on Mac 4 is stamped 15:56:08 and
records pf as still disabled at that point. But
`P2C-02` shows "Enabled for 00:00:23" at 15:56:28, which points to about
15:56:05. The few seconds between the two are not explained. A
request to `:3002` that was in flight at that moment was reset, because its
connection had no pf state (likely, not tested). With `max_fails=1`, that
single failure marked B down for `fail_timeout=10s`. A was already stopped,
so nginx had no live upstream and returned 502 until about 15:56:18.

How that fits the log and Mac 1's polling:

- Backend A (Mac 3) was stopped on purpose for the drill from 15:54:07 to
  15:57:52 (confirmed by Mac 3 on #43).
- The edge's upstreams use `max_fails=1 fail_timeout=10s` and no `keepalive`
  (`02_config/phase2/snapshots/nginx-edge-mac2.conf`), so nginx opens a new
  backend connection per request and one failure takes a backend out for 10 s.
- The first 15:56:08 line names `10.7.3.254:3002`: that is the reset request.
  The later lines show `upstream=teamX_backends (502)` with no address, which
  is nginx's "no live upstreams". It did not try a backend.
- The 502s ended when `fail_timeout` ran out at about 15:56:18, matching Mac 1's
  200s from 15:56:19. Mac 2's last logged 502 is at 15:56:09 only because Mac 1
  sent nothing between 15:56:09 and 15:56:19.

The burst length came from `fail_timeout`, not from how long pf took to load.
This was two planned changes overlapping, not an HA failure. Cause analysis
by Mac 4 in the #43 review.

## Effect on the evidence

None of the P2-D screenshots fall in the burst:
`P2D-02` was taken at 15:56:46 and shows 6 × `HTTP/2 200` from Backend B.

For the final demo, change one thing at a time: load pf rules before
stopping a backend, and check both upstreams are healthy first.
