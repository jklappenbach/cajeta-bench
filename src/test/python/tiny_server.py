#!/usr/bin/env python3
"""The service ServiceTests start: tiny_server.py PORT [MODE].

GET /health answers 200; GET /big makes the process hold another 64 MiB
(written, so it is resident) and answers 200. MODE:
  slow         sleep 30 s before listening (never ready within the test)
  exit         exit 3 at once (dies before ready)
  ignore-term  ignore SIGTERM (the stop must fall back to SIGKILL)
"""
import http.server
import signal
import sys
import time

port = int(sys.argv[1])
mode = sys.argv[2] if len(sys.argv) > 2 else ""
if mode == "exit":
    sys.exit(3)
if mode == "slow":
    time.sleep(30)
if mode == "ignore-term":
    signal.signal(signal.SIGTERM, signal.SIG_IGN)

held = []


class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/big":
            held.append(b"x" * (64 * 1024 * 1024))
        code = 200 if self.path in ("/health", "/big") else 404
        self.send_response(code)
        self.send_header("Content-Length", "2")
        self.end_headers()
        self.wfile.write(b"ok")

    def log_message(self, *args):
        pass


http.server.HTTPServer(("127.0.0.1", port), Handler).serve_forever()
