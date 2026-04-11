"""HTTP echo server benchmark — respond with fixed JSON
Measure with: wrk -t2 -c100 -d5s http://localhost:8080/
"""
from http.server import HTTPServer, BaseHTTPRequestHandler
import sys

BODY = b'{"status":"ok","count":42}'

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(BODY)))
        self.end_headers()
        self.wfile.write(BODY)

    def log_message(self, format, *args):
        pass  # suppress logging

print("Python http_echo listening on :8080", file=sys.stderr)
HTTPServer(("0.0.0.0", 8080), Handler).serve_forever()
