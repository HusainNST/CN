from __future__ import annotations

import hashlib
import json
import os
import socket
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

"""Shared CN Project Phase 1 backend for Mac 3 and Mac 4.

Run Backend A on Mac 3:

    BACKEND_ID=A PORT=3001 python3 server.py

Run Backend B on Mac 4:

    BACKEND_ID=B PORT=3002 python3 server.py

The process uses only the Python standard library and binds to every network
interface so Mac 2's nginx edge can reach it over the private LAN.
"""



BACKEND = os.environ.get("BACKEND_ID", "").strip().upper()
BACKEND_ID = BACKEND  # compatibility name used by the original Mac 4 starter
PORT_VALUE = os.environ.get("PORT", "").strip()
try:
    PORT: int | None = int(PORT_VALUE) if PORT_VALUE else None
except ValueError:
    PORT = None
HOST = "0.0.0.0"


# Keep this representation independent of backend identity so both servers
# produce identical bytes and the same ETag for cache revalidation.
CACHED_BODY = (
    json.dumps(
        {
            "service": "private network service",
            "resource": "cacheable-info",
            "version": 1,
            "note": "Shared cacheable response for both backends.",
        },
        indent=2,
    ).encode("utf-8")
    + b"\n"
)
CACHED_ETAG = '"' + hashlib.sha256(CACHED_BODY).hexdigest()[:16] + '"'


def now() -> str:
    """Return a compact UTC timestamp for response bodies and logs."""

    return datetime.now(timezone.utc).isoformat(timespec="seconds")


class Handler(BaseHTTPRequestHandler):
    """HTTP/1.1 handler for health, status, and cache demonstrations."""

    server_version = f"CNBackend-{BACKEND}/1.0"
    protocol_version = "HTTP/1.1"

    def _send(self, code: int, obj=None, raw: bytes | None = None, headers=None) -> None:
        body = raw if raw is not None else (
            json.dumps(obj, indent=2).encode("utf-8") + b"\n" if obj is not None else b""
        )

        self.send_response(code)
        self.send_header("X-Backend", BACKEND)
        for key, value in (headers or {}).items():
            self.send_header(key, value)
        if code != 304:
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
        self.end_headers()

        if code != 304 and self.command != "HEAD":
            self.wfile.write(body)

    def do_GET(self) -> None:
        path = self.path.split("?", 1)[0]

        if path == "/":
            self._send(
                200,
                {
                    "service": f"Backend {BACKEND}",
                    "status": "running",
                    "host": socket.gethostname(),
                    "port": PORT,
                    "time": now(),
                },
                headers={"Cache-Control": "no-store"},
            )
        elif path == "/api/status":
            self._send(
                200,
                {
                    "status": "ok",
                    "backend": BACKEND,
                    "port": PORT,
                    "time": now(),
                },
                headers={"Cache-Control": "no-store"},
            )
        elif path == "/api/cached":
            cache_headers = {
                "Cache-Control": "public, max-age=60",
                "ETag": CACHED_ETAG,
            }
            if_none_match = self.headers.get("If-None-Match", "")
            requested_tags = [tag.strip() for tag in if_none_match.split(",")]
            if CACHED_ETAG in requested_tags or "*" in requested_tags:
                self._send(304, headers=cache_headers)
            else:
                self._send(200, raw=CACHED_BODY, headers=cache_headers)
        else:
            self._send(
                404,
                {"error": "not found", "backend": BACKEND, "path": path},
            )

    do_HEAD = do_GET

    def log_message(self, format: str, *args: object) -> None:
        """Show the edge peer and forwarded client in the viva evidence."""

        forwarded_for = (
            self.headers.get("X-Forwarded-For", "-")
            if getattr(self, "headers", None)
            else "-"
        )
        print(
            f"[{now()}] Backend {BACKEND} | "
            f"peer={self.client_address[0]}:{self.client_address[1]} | "
            f"X-Forwarded-For={forwarded_for} | {format % args}",
            flush=True,
        )


# Keep the original starter's import name available to existing helpers.
RequestHandler = Handler


def main() -> None:
    if BACKEND not in {"A", "B"}:
        raise SystemExit("Set BACKEND_ID to A or B")
    if PORT is None or not 1 <= PORT <= 65535:
        raise SystemExit("Set PORT to an integer between 1 and 65535")
    server = ThreadingHTTPServer((HOST, PORT), Handler)
    print(
        f"Backend {BACKEND} listening on http://{HOST}:{PORT} (Ctrl+C to stop)",
        flush=True,
    )
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print(f"Backend {BACKEND} stopped.", flush=True)
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
