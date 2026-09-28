# Trishit — Mac 3: Backend A, caching, and architecture package

**Lead:** Backend A in Task C, Task F (caching), architecture document and package, and the one-backend-stopped demonstration.
**Mac 3 address in the current table:** 10.144.232.1/24 on en0; gateway 10.144.232.191. Recheck on lab day.

The shared source is 03_backend_code/server.py. It runs as A or B depending on BACKEND_ID and PORT. Replace teamX with the assigned team number where it appears in commands and diagrams.

**Checklist rule:** mark an item when the check succeeds, then write the proof path.

## 1. Join and check the LAN — Task A

- [x] Mac 3's current recorded IP, prefix, gateway, and ifconfig MAC are in 01_architecture/architecture_doc.md and 01_architecture/ip_table.md.
- [ ] Recheck Mac 3 on the lab LAN. ifconfig reported MAC 3e:1b:0f:b0:84:64, while networksetup reported Wi-Fi ID 10:9f:41:c1:7f:a5. Confirm which identifier is active and correct the shared table if needed.
- [ ] Label the terminal, keep the Mac awake, and ping Macs 1, 2, and 4.

      export PS1="[Mac3-BackendA-Trishit] %~ %# "
      caffeinate -dims &
      date
      networksetup -listallhardwareports | grep -A2 "Wi-Fi"
      ipconfig getifaddr en0
      ifconfig en0 | grep -E "ether|inet "
      route -n get default | grep -E "gateway|interface"
      ping -c 4 <MAC1_IP>
      ping -c 4 <MAC2_IP>
      ping -c 4 <MAC4_IP>

   Save Mac 3's network and ping evidence under 04_evidence/A_lan/.

## 2. Run Backend A — Task C

- [x] The shared server source and A/B usage guide exist at 03_backend_code/server.py and 03_backend_code/README.md.
- [ ] From 03_backend_code/, start the service as A on TCP 3001. Leave this terminal open.

      BACKEND_ID=A PORT=3001 python3 server.py

- [ ] In a second terminal, confirm the process listens on all interfaces and both required endpoints return HTTP 200 with X-Backend: A.

      date
      lsof -nP -iTCP:3001 -sTCP:LISTEN
      curl -i http://localhost:3001/
      curl -i http://localhost:3001/api/status

   The listener should be *:3001 or 0.0.0.0:3001, not only 127.0.0.1. Save a full-window screenshot under 04_evidence/C_backends/.

- [ ] Ask Sarvesh to run curl -i http://<MAC3_IP>:3001/api/status from Mac 2. Confirm HTTP 200, X-Backend: A, and JSON showing backend A. Save the result under 04_evidence/C_backends/.

## 3. Demonstrate HTTP caching — Task F

- [x] The current source returns Cache-Control, a stable shared ETag, and a 304 response for a matching If-None-Match value on /api/cached.
- [ ] Start both backends and nginx. From a client, request the cache endpoint through the HTTPS edge.

      curl -i https://app.teamX.test/api/cached

   Expected: HTTP 200, Cache-Control: public, max-age=60, and an ETag header.

- [ ] Send the ETag back in a conditional request. The second response must be HTTP 304 with no response body.

      ETAG=$(curl -sI https://app.teamX.test/api/cached | awk 'tolower($1)=="etag:" {print $2}' | tr -d '\r')
      curl -i -H "If-None-Match: $ETAG" https://app.teamX.test/api/cached

- [ ] Confirm /api/status instead returns Cache-Control: no-store.

      curl -sI https://app.teamX.test/api/status

- [ ] Save the 200/ETag, 304, and no-store output under 04_evidence/F_caching/. Optionally use browser Developer Tools → Network to show a fresh browser cache hit or revalidation.
- [ ] Explain: a fresh max-age response can be reused without contacting the server; a conditional request sends If-None-Match and may receive 304 with no body; an uncached request receives a full 200 response.

## 4. Demonstrate stopping one backend — Task H

- [ ] With both backends initially working, save a few requests showing A and B. Stop Backend A with Ctrl+C.
- [ ] From Mac 1 or Mac 4, make six requests through the HTTPS name. All should return HTTP 200 from B while A is stopped.

      for i in 1 2 3 4 5 6; do
        curl -s -D - -o /dev/null https://app.teamX.test/api/status | grep -iE "^HTTP|x-backend"
      done

- [ ] Ask Sarvesh to save the nginx log showing the failed A attempt and retry to B. Save client proof under 04_evidence/H_failures/.
- [ ] Restart Backend A with the same command. Repeat the requests and confirm both A and B return. Save the restored proof.

## 5. Finish the team architecture and package — Tasks A and Section 9

- [x] The team topology, editable topology source, protocol request-flow diagram, and shared IP table exist in 01_architecture/.
- [ ] Verify every IP, mask, gateway, MAC, role, and service port on the live LAN. Resolve the Mac 3 MAC discrepancy noted above.
- [ ] Read the architecture document as a team. Confirm it shows all four roles and the path DNS → TCP → TLS → HTTP → backend.
- [ ] Save any required export in 01_architecture/ and make sure the evidence folder is organized for a reviewer to find proof quickly.
- [ ] Check the configuration bundle and evidence folder using the team checklist.

## 6. Before the review

- [ ] Present demo steps 1, 7, and 8: topology, caching, and stop A while B continues serving; then restore A.
- [ ] Explain the shared backend implementation, cache headers/ETag, round robin, and backend failover.
- [ ] Check off finished items in 06_phase1_checklists/team_overview.md and add evidence paths.
