"""Polite HTTP for the public music services (MusicBrainz, ListenBrainz):
a pause between requests, an identifying User-Agent, and patience with
their 503s. Standard library only."""

from __future__ import annotations

import json
import logging
import threading
import time
import urllib.error
import urllib.parse
import urllib.request

log = logging.getLogger("recommender")


class PoliteClient:
    """GETs JSON from base, at most one request per min_interval seconds."""

    query: dict = {}  # added to every request

    def __init__(self, user_agent: str, base: str, min_interval: float = 1.1, opener=None, sleep=time.sleep):
        self.user_agent = user_agent
        self.min_interval = min_interval
        self.base = base.rstrip("/")
        self.open = opener or (lambda req: urllib.request.urlopen(req, timeout=30))
        self.sleep = sleep
        self._lock = threading.Lock()
        self._last = 0.0

    def get(self, path: str, query: dict):
        url = f"{self.base}/{path}?{urllib.parse.urlencode({**query, **self.query})}"
        attempts = 5
        for attempt in range(attempts):
            with self._lock:
                wait = self._last + self.min_interval - time.monotonic()
                if wait > 0:
                    self.sleep(wait)
                self._last = time.monotonic()
            req = urllib.request.Request(url, headers={"User-Agent": self.user_agent, "Accept": "application/json"})
            try:
                with self.open(req) as resp:
                    return json.loads(resp.read())
            except urllib.error.HTTPError as e:
                # 503 / 429: rate limited or busy, which happens now and then
                # even within the limits. Wait as told, longer each time.
                if e.code in (429, 503) and attempt < attempts - 1:
                    after = e.headers.get("Retry-After") if e.headers else None
                    delay = 5 * 2**attempt
                    if after and str(after).isdigit():
                        delay = max(delay, int(after))
                    self.sleep(delay)
                    continue
                raise
        raise RuntimeError("unreachable")


class SlowWorker:
    """Runs run_once until it finds nothing to do, then waits poll seconds;
    on errors, waits longer each time."""

    label = "worker"

    def __init__(self, sleep=time.sleep, poll: float = 3600):
        self.sleep = sleep
        self.poll = poll

    def run_once(self) -> int:
        raise NotImplementedError

    def run_forever(self) -> None:
        backoff = 30.0
        while True:
            try:
                n = self.run_once()
                backoff = 30.0
            except Exception as e:  # server or the service down, network...
                log.warning("%s: %s; retrying in %.0f s", self.label, e, backoff)
                self.sleep(backoff)
                backoff = min(backoff * 2, 3600)
                continue
            if n == 0:
                self.sleep(self.poll)
