import io
import json
import unittest
import urllib.parse

from ttyfm_recommender.listenbrainz import ALGORITHM, DiscoveryWorker, ListenBrainz


def fake_lb(data, seen):
    def opener(req):
        q = dict(urllib.parse.parse_qsl(urllib.parse.urlparse(req.full_url).query))
        seen.append((urllib.parse.urlparse(req.full_url).path, q, req.get_header("User-agent")))
        return io.BytesIO(json.dumps(data.get(q["artist_mbids"], [])).encode())

    return opener


SIA = [
    {"artist_mbid": "rihanna", "name": "Rihanna", "comment": "Barbadian R&B/pop singer", "score": 6209},
    {"artist_mbid": "coldplay", "name": "Coldplay", "comment": "", "score": 6230},
    {"artist_mbid": "sia", "name": "Sia", "score": 9999},  # itself: out
    {"artist_mbid": "", "name": "No id", "score": 10},  # incomplete: out
]


class FakeClient:
    def __init__(self, jobs):
        self.jobs = jobs
        self.saved = {}

    def discovery_queue(self, limit=10):
        jobs, self.jobs = self.jobs, []
        return jobs

    def save_similar(self, artist_id, body):
        self.saved[artist_id] = body


class ListenBrainzTest(unittest.TestCase):
    def test_similar_artists(self):
        seen = []
        lb = ListenBrainz("tty.fm/test ( x )", opener=fake_lb({"sia": SIA}, seen), sleep=lambda s: None)
        got = lb.similar_artists("sia")
        self.assertEqual([a["name"] for a in got], ["Coldplay", "Rihanna"])  # closest first
        self.assertEqual(
            got[1], {"mbid": "rihanna", "name": "Rihanna", "comment": "Barbadian R&B/pop singer", "score": 6209.0}
        )
        path, q, ua = seen[0]
        self.assertEqual(path, "/similar-artists/json")
        self.assertEqual(q["algorithm"], ALGORITHM)
        self.assertEqual(ua, "tty.fm/test ( x )")
        self.assertEqual(lb.similar_artists("unknown"), [])

    def test_worker(self):
        seen = []
        lb = ListenBrainz("ua", opener=fake_lb({"sia": SIA}, seen), sleep=lambda s: None)
        client = FakeClient([{"artist_id": 1, "name": "Sia", "mbid": "sia"}])
        self.assertEqual(DiscoveryWorker(client, lb).run_once(), 1)
        self.assertEqual(len(client.saved[1]["items"]), 2)
        self.assertEqual(DiscoveryWorker(client, lb).run_once(), 0)


if __name__ == "__main__":
    unittest.main()
