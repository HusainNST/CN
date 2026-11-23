# Troubleshooting drill findings (Extension F)

Both drills ran in the Docker emulation and followed
[troubleshooting_runbook.md](../../02_config/phase2/troubleshooting_runbook.md).
The script injected the faults, so these drills were **not blind**. Issue
P2-17 still needs two blind drills on the real Macs, with one teammate
injecting the fault.

Full transcript: [P2F_troubleshooting_drills.txt](../P2_docker_emulation/P2F_troubleshooting_drills.txt)

## Drill 1: wrong A record on the primary DNS

| Step | Observation |
| --- | --- |
| Symptom | From Mac 1, `curl https://app.teamX.test/api/status` fails: `Failed to connect to app.teamX.test port 443 after 3060 ms` |
| Layer 1 DNS | `dig app.teamX.test` returns `10.77.0.30`, not the edge `10.77.0.20`. `dig @10.77.0.10` (primary) says `10.77.0.30`; `dig @10.77.0.80` (backup) says `10.77.0.20` |
| Root cause | `host-record` for `app.teamX.test` on Mac 1 points at an address with no edge |
| Fix | Re-render with `mac1-dns-phase2.sh <MAC1_IP> <MAC2_IP>`, restart dnsmasq, flush the client cache |
| Verify | `dig` returns `10.77.0.20`; HTTPS returns `HTTP/2 200` |

Why Layer 1 first: a connect failure looks like a TCP problem, but TCP was
going to the wrong host. The two DNS servers disagreeing pointed straight at
the primary's record. The backup did not hide this fault, because the backup
is only used when the primary does not answer at all. A wrong answer still
counts as an answer.

## Drill 2: backend firewall allows the wrong edge IP

| Step | Observation |
| --- | --- |
| Symptom | Every request returns `HTTP/2 200`, but six in a row all say `X-Backend: B` |
| Layer 1 DNS | `dig app.teamX.test` returns the edge `10.77.0.20`, correct |
| Layer 2 TCP | From Mac 2: `nc -vz 10.77.0.80 3001` gives `Connection refused`; `nc -vz 10.77.0.90 3002` succeeds |
| Layer 2 pf | Mac 3 anchor accepts 3001 only from `10.77.0.71`; the edge's server side address is `10.77.0.70`, so it gets a TCP reset |
| Root cause | pf isolation applied with a mistyped edge IP |
| Fix | Roll back, then `pf-backend-isolate.sh 3001 <MAC2_IP>` with the correct IP |
| Verify | After `fail_timeout` (10 s), responses alternate A and B again |

Lesson: failover hid the fault from users. Every request succeeded, so the only
sign was the backend header. On a real system this is why health monitoring
must alert on a backend being marked down, not only on user-facing errors.
