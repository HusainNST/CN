# Shared Backend Source - A and B

This directory contains one Python REST backend used by both application
servers. Mac 3 runs it as **Backend A** on TCP 3001; Mac 4 runs it as
**Backend B** on TCP 3002. The environment variables select the identity and
port, so both machines run the same `server.py` source with different values.

The service uses Python's standard library and binds to `0.0.0.0` so Mac 2's
Nginx edge can reach it over the private LAN. `BACKEND_ID` and `PORT` must be
set at launch; the server has no default backend role or port. The cacheable
response is backend-independent, so both processes return identical content
and ETags without team-specific configuration.

## Endpoints

| Method | Path | Response | Cache behavior |
|---|---|---|---|
| `GET` | `/` | Service status, backend ID, host, port, and UTC time | `Cache-Control: no-store` |
| `GET` | `/api/status` | JSON status, backend ID, port, and UTC time | `Cache-Control: no-store` |
| `GET` | `/api/cached` | Shared cacheable JSON representation | `Cache-Control: public, max-age=60` and stable `ETag` |
| `HEAD` | These endpoints | Same headers as `GET`, without a response body | Same policy as the corresponding `GET` |
| `GET` | Unknown path | JSON 404 with backend ID and requested path | No cache header |

Every response includes `X-Backend: A` or `X-Backend: B`. A matching
`If-None-Match` request to `/api/cached` returns `304 Not Modified` without a
body.

## Start the backends

Run each command on its assigned Mac, from this directory. Leave each server
terminal open during the demo.

**Mac 3 - Backend A:**

```sh
BACKEND_ID=A PORT=3001 python3 server.py
```

**Mac 4 - Backend B:**

```sh
BACKEND_ID=B PORT=3002 python3 server.py
```

Stop a backend with `Ctrl+C` in its terminal.

## Check each backend locally

On Mac 3:

```sh
lsof -nP -iTCP:3001 -sTCP:LISTEN
curl -i http://localhost:3001/api/status
```

On Mac 4:

```sh
lsof -nP -iTCP:3002 -sTCP:LISTEN
curl -i http://localhost:3002/api/status
```

Each response should be HTTP 200, include the matching `X-Backend` header, and
return JSON with the corresponding backend ID.

## Check reachability from the edge

From Mac 2, replace the address placeholders with the backend Macs' current
LAN addresses:

```sh
curl -i http://<MAC3_IP>:3001/api/status
curl -i http://<MAC4_IP>:3002/api/status
```

Both requests should return HTTP 200. If a local check works but a Mac 2 check
does not, check that the service is bound to `0.0.0.0`, all Macs are on the
same LAN, and the backend Mac's firewall permits the service port.

## Demonstrate caching

Request `/api/cached` from each backend and compare the `ETag` response header;
the values should match because the cacheable body is identical on A and B.
Copy the returned ETag into a conditional request to either backend:

```sh
curl -i http://localhost:3001/api/cached
curl -i -H 'If-None-Match: "paste-etag-here"' http://localhost:3001/api/cached
```

The first response is HTTP 200 with a body. The matching conditional request
is HTTP 304 with no body. Repeat against port 3002 to verify the shared ETag.

## Integration with Nginx

Mac 2 configures Backend A (`<MAC3_IP>:3001`) and Backend B
(`<MAC4_IP>:3002`) as upstream targets. Clients request the edge hostname; they
do not choose a backend directly. Repeated edge requests should show both
`X-Backend: A` and `X-Backend: B`. Stopping one backend is the failover demo;
Nginx must be configured to retry the other target for requests to continue
succeeding.
