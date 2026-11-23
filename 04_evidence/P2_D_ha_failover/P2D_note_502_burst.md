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

Both backends were unavailable to the edge at the same moment, so nginx had
no healthy upstream to fail over to:

- Backend A (Mac 3) was stopped on purpose for the drill from 15:54:07 to
  15:57:52 (confirmed by Mac 3 on #43).
- Mac 4's pf anchor for Backend B (`:3002`, #12) was being loaded at 15:56
  (`P2C-02` in #42).

This was two planned changes overlapping, not an HA failure. Once Mac 4's pf
rule was in place and allowed Mac 2, Backend B served every request and the
502s stopped (last 502 in Mac 2's log at 15:56:09).

## Effect on the evidence

None of the P2-D screenshots fall in the burst:
`P2D-02` was taken at 15:56:46 and shows 6 × `HTTP/2 200` from Backend B.

For the final demo, change one thing at a time: load pf rules before
stopping a backend, and check both upstreams are healthy first.
