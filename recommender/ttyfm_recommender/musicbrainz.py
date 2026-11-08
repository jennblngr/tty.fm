"""MusicBrainz lookups for the new releases (standard library only).

MusicBrainz asks for at most one request per second and a User-Agent that
names the application and a way to reach its author; the client waits
between requests and backs off when told to (HTTP 503)."""

from __future__ import annotations

import json
import logging
import re
import threading
import time
import unicodedata
import urllib.error
import urllib.parse
import urllib.request

BASE = "https://musicbrainz.org/ws/2"
KINDS = ("album", "ep", "single")

log = logging.getLogger("recommender")


def title_key(title: str) -> str:
    """Compares titles across editions, like the server: no parenthesised
    part, no accents, no punctuation, lower case."""
    t = re.sub(r"\s*[\(\[][^\)\]]*[\)\]]", "", title) or title
    t = unicodedata.normalize("NFD", t)
    t = "".join(c for c in t if unicodedata.category(c) != "Mn")
    t = re.sub(r"[^\w\s]", " ", t.lower())
    return " ".join(t.split())


class MusicBrainz:
    def __init__(self, user_agent: str, min_interval: float = 1.1, base: str = BASE, opener=None, sleep=time.sleep):
        self.user_agent = user_agent
        self.min_interval = min_interval
        self.base = base.rstrip("/")
        self.open = opener or (lambda req: urllib.request.urlopen(req, timeout=30))
        self.sleep = sleep
        self._lock = threading.Lock()
        self._last = 0.0

    def get(self, path: str, query: dict) -> dict:
        url = f"{self.base}/{path}?{urllib.parse.urlencode({**query, 'fmt': 'json'})}"
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
                # 503: rate limited or busy, which happens now and then even
                # within the limits. Wait as told, longer each time.
                if e.code == 503 and attempt < attempts - 1:
                    after = (e.headers or {}).get("Retry-After") if e.headers else None
                    delay = 5 * 2**attempt
                    if after and str(after).isdigit():
                        delay = max(delay, int(after))
                    self.sleep(delay)
                    continue
                raise
        raise RuntimeError("unreachable")

    def find_artist(self, name: str, albums: list[str]) -> str | None:
        """The MusicBrainz id of the artist called name. Between namesakes,
        the one whose releases share the most titles with albums; None when
        no artist has exactly this name."""
        res = self.get("artist", {"query": f'artist:"{name}"', "limit": 10})
        want = name.casefold()
        same = [a for a in res.get("artists", []) if a.get("name", "").casefold() == want and a.get("score", 0) >= 90]
        if not same:
            return None
        if len(same) == 1 or not albums:
            return same[0]["id"]
        keys = {title_key(a) for a in albums}

        def overlap(artist_id: str) -> int:
            return len(keys & {title_key(r["title"]) for r in self.release_groups(artist_id)})

        return max(same[:3], key=lambda a: overlap(a["id"]))["id"]

    def release_groups(self, artist_id: str) -> list[dict]:
        """The artist's albums, EPs and singles, without compilations, live
        albums, remixes and other secondary types; those without a date are
        left out."""
        out: list[dict] = []
        offset = 0
        while True:
            res = self.get(
                "release-group", {"artist": artist_id, "type": "|".join(KINDS), "limit": 100, "offset": offset}
            )
            groups = res.get("release-groups", [])
            for g in groups:
                kind = (g.get("primary-type") or "").lower()
                date = g.get("first-release-date") or ""
                if kind in KINDS and not g.get("secondary-types") and re.fullmatch(r"\d{4}(-\d{2}(-\d{2})?)?", date):
                    out.append({"mbid": g["id"], "title": g.get("title", ""), "kind": kind, "released": date})
            offset += len(groups)
            if not groups or offset >= res.get("release-group-count", 0):
                return out


class ReleaseWorker:
    """Looks the library's album artists up on MusicBrainz, as the server
    asks (each at most once a week), and sends their releases back."""

    def __init__(self, client, mb: MusicBrainz, poll: float = 3600):
        self.client = client
        self.mb = mb
        self.poll = poll

    def process(self, job: dict) -> dict:
        mbid = job.get("mbid") or self.mb.find_artist(job["name"], job.get("albums", []))
        releases = self.mb.release_groups(mbid) if mbid else []
        report = {"mbid": mbid, "releases": releases}
        self.client.save_releases(job["artist_id"], report)
        if mbid:
            log.info("releases of %s: %d on MusicBrainz", job["name"], len(releases))
        else:
            log.info("releases of %s: not found on MusicBrainz", job["name"])
        return report

    def run_once(self) -> int:
        jobs = self.client.release_queue(limit=10)
        for job in jobs:
            self.process(job)
        return len(jobs)

    def run_forever(self) -> None:
        backoff = 30.0
        while True:
            try:
                n = self.run_once()
                backoff = 30.0
            except Exception as e:  # server or MusicBrainz down, network...
                log.warning("new releases: %s; retrying in %.0f s", e, backoff)
                self.mb.sleep(backoff)
                backoff = min(backoff * 2, 3600)
                continue
            if n == 0:
                self.mb.sleep(self.poll)
