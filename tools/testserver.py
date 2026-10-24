#!/usr/bin/env python3
"""Tiny local HTTPS-less server for launcher tests.

Not part of the shipped launcher - it exists so the CI suite can prove:
  * plain downloads
  * HTTP Range resume (the "interrupted download" scenario)
  * throttled downloads (so a cancel can happen mid-flight)
  * request accounting (to prove delta updates only fetch what changed)

Usage:
  python3 tools/testserver.py --root /tmp/fixtures --port 8765
Routes:
  /version.json            -> <root>/version.json
  /manifests/<name>.json   -> <root>/manifests/<name>.json
  /packs/<file>            -> <root>/packs/<file>  (Range supported)
  /slow/packs/<file>[?bps=] -> same, throttled to bps bytes/sec (default 400000)
  /_requests               -> JSON list of served requests
  /_reset                  -> clears the request list
  /_health                 -> "ok"
"""
from __future__ import annotations

import argparse
import json
import os
import re
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

ROOT = "."
REQUESTS: list[dict] = []
LOCK = threading.Lock()
RANGE_RE = re.compile(r"bytes=(\d+)-(\d*)")


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt, *args):  # keep CI logs readable
        pass

    def _json(self, code: int, payload) -> None:
        body = json.dumps(payload).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):  # noqa: N802
        path, _, query = self.path.partition("?")
        params = {}
        for kv in query.split("&"):
            if "=" in kv:
                k, v = kv.split("=", 1)
                params[k] = v

        if path == "/_health":
            self._json(200, {"ok": True})
            return
        if path == "/_requests":
            with LOCK:
                self._json(200, list(REQUESTS))
            return
        if path == "/_reset":
            with LOCK:
                REQUESTS.clear()
            self._json(200, {"ok": True})
            return

        throttle = 0
        if path.startswith("/slow/"):
            path = "/" + path[len("/slow/"):]
            throttle = int(params.get("bps", "400000"))

        rel = path.lstrip("/")
        full = os.path.join(ROOT, rel)
        if not os.path.isfile(full):
            self._json(404, {"error": "not found", "path": rel})
            return

        size = os.path.getsize(full)
        start, end = 0, size - 1
        status = 200
        rng = self.headers.get("Range")
        if rng:
            m = RANGE_RE.search(rng)
            if m:
                start = int(m.group(1))
                if m.group(2):
                    end = min(int(m.group(2)), size - 1)
                if start >= size:
                    self.send_response(416)
                    self.send_header("Content-Range", f"bytes */{size}")
                    self.send_header("Content-Length", "0")
                    self.end_headers()
                    return
                status = 206

        length = end - start + 1
        with LOCK:
            REQUESTS.append({
                "path": path,
                "range": rng or "",
                "start": start,
                "bytes": length,
                "at": time.time(),
                "throttle": throttle,
            })

        self.send_response(status)
        self.send_header("Content-Type", "application/octet-stream")
        self.send_header("Content-Length", str(length))
        self.send_header("Accept-Ranges", "bytes")
        if status == 206:
            self.send_header("Content-Range", f"bytes {start}-{end}/{size}")
        self.end_headers()

        chunk_size = 32768
        sent = 0
        with open(full, "rb") as fh:
            fh.seek(start)
            while sent < length:
                want = min(chunk_size, length - sent)
                data = fh.read(want)
                if not data:
                    break
                try:
                    self.wfile.write(data)
                except (BrokenPipeError, ConnectionResetError):
                    return
                sent += len(data)
                if throttle > 0:
                    time.sleep(len(data) / throttle)


def main() -> None:
    global ROOT
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default=".")
    ap.add_argument("--port", type=int, default=8765)
    args = ap.parse_args()
    ROOT = os.path.abspath(args.root)
    srv = ThreadingHTTPServer(("127.0.0.1", args.port), Handler)
    srv.daemon_threads = True
    print(f"testserver serving {ROOT} on http://127.0.0.1:{args.port}", flush=True)
    srv.serve_forever()


if __name__ == "__main__":
    main()
