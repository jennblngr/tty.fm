"""Discovery: artists similar to the liked ones, from ListenBrainz's
similar-artists dataset (labs API, no token needed)."""

from __future__ import annotations

import logging
import time

from .web import PoliteClient, SlowWorker

BASE = "https://labs.api.listenbrainz.org"
# The dataset ListenBrainz uses on its own artist pages: listening sessions
# over about 20 years.
ALGORITHM = "session_based_days_7500_session_300_contribution_5_threshold_10_limit_100_filter_True_skip_30"

log = logging.getLogger("recommender")


class ListenBrainz(PoliteClient):
    def __init__(self, user_agent: str, min_interval: float = 1.1, base: str = BASE, opener=None, sleep=time.sleep):
        super().__init__(user_agent, base, min_interval, opener, sleep)

    def similar_artists(self, mbid: str, limit: int = 25) -> list[dict]:
        """The artists closest to mbid, closest first."""
        res = self.get("similar-artists/json", {"artist_mbids": mbid, "algorithm": ALGORITHM})
        items = [
            {
                "mbid": a["artist_mbid"],
                "name": a.get("name") or "",
                "comment": a.get("comment") or "",
                "score": float(a.get("score") or 0),
            }
            for a in (res if isinstance(res, list) else [])
            if a.get("artist_mbid") and a.get("name") and a.get("artist_mbid") != mbid
        ]
        items.sort(key=lambda a: a["score"], reverse=True)
        return items[:limit]


class DiscoveryWorker(SlowWorker):
    """Fetches the similar artists of each liked artist whose MusicBrainz id
    is known (at most once a week, as the server asks)."""

    label = "discovery"

    def __init__(self, client, lb: ListenBrainz, poll: float = 3600):
        super().__init__(lb.sleep, poll)
        self.client = client
        self.lb = lb

    def run_once(self) -> int:
        jobs = self.client.discovery_queue(limit=10)
        for job in jobs:
            items = self.lb.similar_artists(job["mbid"])
            self.client.save_similar(job["artist_id"], {"items": items})
            log.info("similar to %s: %d on ListenBrainz", job["name"], len(items))
        return len(jobs)
