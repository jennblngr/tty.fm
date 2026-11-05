import json
import os
import tempfile
import threading
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

from ttyfm_recommender.client import Client


class FakeServer(BaseHTTPRequestHandler):
    logins = 0
    valid = set()
    reports = {}

    def log_message(self, *args):
        pass

    def _send(self, status, body=None):
        self.send_response(status)
        self.end_headers()
        if body is not None:
            self.wfile.write(json.dumps(body).encode())

    def _body(self):
        n = int(self.headers.get("Content-Length") or 0)
        return json.loads(self.rfile.read(n)) if n else None

    def _authed(self):
        return self.headers.get("Authorization", "").removeprefix("Bearer ") in FakeServer.valid

    def do_POST(self):
        body = self._body()
        if self.path == "/api/v1/auth/login" and body["password"] == "pw" and body["device_name"] == "recommender":
            FakeServer.logins += 1
            tok = f"tok{FakeServer.logins}"
            FakeServer.valid = {tok}
            return self._send(200, {"token": tok})
        self._send(401, {"error": "bad credentials"})

    def do_GET(self):
        if not self._authed():
            return self._send(401, {"error": "unauthorized"})
        self._send(200, {"items": [{"id": 7, "path": "a.flac", "file_mtime": 1, "duration_ms": 1}]})

    def do_PUT(self):
        if not self._authed():
            return self._send(401, {"error": "unauthorized"})
        FakeServer.reports[self.path] = self._body()
        self._send(204)


class ClientTest(unittest.TestCase):
    def setUp(self):
        self.srv = ThreadingHTTPServer(("127.0.0.1", 0), FakeServer)
        threading.Thread(target=self.srv.serve_forever, daemon=True).start()
        self.url = f"http://127.0.0.1:{self.srv.server_port}"
        self.token_file = os.path.join(tempfile.mkdtemp(), "state", "token")

    def tearDown(self):
        self.srv.shutdown()
        self.srv.server_close()

    def test_login_reuse_and_relogin(self):
        c = Client(self.url, "admin", "pw", self.token_file)
        self.assertEqual(c.queue()[0]["id"], 7)
        c.report(7, {"analyzer": "x"})
        self.assertEqual(FakeServer.reports["/api/v1/tracks/7/analysis"], {"analyzer": "x"})
        logins = FakeServer.logins

        # A restart reuses the saved token instead of creating a device.
        c2 = Client(self.url, "admin", "pw", self.token_file)
        c2.queue()
        self.assertEqual(FakeServer.logins, logins)

        # A revoked token triggers one new login.
        FakeServer.valid = set()
        c2.queue()
        self.assertEqual(FakeServer.logins, logins + 1)
        with open(self.token_file) as f:
            self.assertEqual(f.read(), c2.token)

    def test_bad_password(self):
        with self.assertRaises(RuntimeError):
            Client(self.url, "admin", "nope").queue()


if __name__ == "__main__":
    unittest.main()
