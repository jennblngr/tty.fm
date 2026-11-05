"""Minimal client of the tty.fm API (standard library only)."""

from __future__ import annotations

import json
import logging
import os
import urllib.error
import urllib.request

API = "/api/v1"

log = logging.getLogger("recommender")


class Unauthorized(Exception):
    pass


class Client:
    """Logs in as a device named "recommender" and keeps its token in
    token_file, so restarts don't pile up devices on the server."""

    def __init__(self, base_url: str, username: str, password: str, token_file: str | None = None):
        self.base = base_url.rstrip("/") + API
        self.username = username
        self.password = password
        self.token_file = token_file
        self.token = self._load_token()

    def _load_token(self) -> str | None:
        if not self.token_file:
            return None
        try:
            with open(self.token_file) as f:
                return f.read().strip() or None
        except FileNotFoundError:
            return None

    def _save_token(self) -> None:
        if not self.token_file or not self.token:
            return
        try:
            os.makedirs(os.path.dirname(self.token_file) or ".", exist_ok=True)
            tmp = self.token_file + ".tmp"
            with open(os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600), "w") as f:
                f.write(self.token)
            os.replace(tmp, self.token_file)
        except OSError as e:  # still works, but each restart registers a new device
            log.warning("cannot save the token in %s: %s", self.token_file, e)

    def _request(self, method: str, path: str, body=None, auth: bool = True):
        data = None if body is None else json.dumps(body).encode()
        req = urllib.request.Request(self.base + path, data=data, method=method)
        req.add_header("Content-Type", "application/json")
        req.add_header("User-Agent", "ttyfm-recommender")
        if auth and self.token:
            req.add_header("Authorization", "Bearer " + self.token)
        try:
            with urllib.request.urlopen(req, timeout=30) as resp:
                raw = resp.read()
        except urllib.error.HTTPError as e:
            if e.code == 401 and auth:
                raise Unauthorized() from e
            detail = e.read().decode(errors="replace")
            raise RuntimeError(f"{method} {path}: HTTP {e.code}: {detail}") from e
        return json.loads(raw) if raw else None

    def login(self) -> None:
        res = self._request(
            "POST",
            "/auth/login",
            {"username": self.username, "password": self.password, "device_name": "recommender", "platform": "server"},
            auth=False,
        )
        self.token = res["token"]
        self._save_token()

    def call(self, method: str, path: str, body=None):
        """Like _request, logging in first (and again once if the token was revoked)."""
        if not self.token:
            self.login()
        try:
            return self._request(method, path, body)
        except Unauthorized:
            self.login()
            return self._request(method, path, body)

    def queue(self, limit: int = 20) -> list[dict]:
        return self.call("GET", f"/analysis/queue?limit={limit}")["items"]

    def report(self, track_id: int, report: dict) -> None:
        self.call("PUT", f"/tracks/{track_id}/analysis", report)
