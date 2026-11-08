import io
import json
import unittest
import urllib.error
import urllib.parse

from ttyfm_recommender.musicbrainz import MusicBrainz, ReleaseWorker, title_key


class FakeMB:
    """Answers like MusicBrainz from canned data, and records each request."""

    def __init__(self, artists, groups, fail_first=0):
        self.artists = artists  # name -> search results
        self.groups = groups  # artist id -> release groups
        self.fail_first = fail_first
        self.requests = []

    def __call__(self, req):
        url = urllib.parse.urlparse(req.full_url)
        q = dict(urllib.parse.parse_qsl(url.query))
        self.requests.append((url.path, q, req.get_header("User-agent")))
        if self.fail_first:
            self.fail_first -= 1
            raise urllib.error.HTTPError(req.full_url, 503, "slow down", {}, io.BytesIO())
        if url.path.endswith("/artist"):
            name = q["query"].removeprefix('artist:"').removesuffix('"')
            body = {"artists": self.artists.get(name, [])}
        else:
            groups = self.groups.get(q["artist"], [])
            off, lim = int(q["offset"]), int(q["limit"])
            body = {"release-groups": groups[off : off + lim], "release-group-count": len(groups)}
        return io.BytesIO(json.dumps(body).encode())


def group(i, title, kind="Album", date="2026-10-01", secondary=()):
    return {"id": f"rg{i}", "title": title, "primary-type": kind, "first-release-date": date,
            "secondary-types": list(secondary)}  # fmt: skip


class FakeClient:
    def __init__(self, jobs):
        self.jobs = jobs
        self.saved = {}

    def release_queue(self, limit=10):
        jobs, self.jobs = self.jobs, []
        return jobs

    def save_releases(self, artist_id, report):
        self.saved[artist_id] = report


class MusicBrainzTest(unittest.TestCase):
    def mb(self, fake):
        self.waits = []
        return MusicBrainz("tty.fm/test ( https://example )", opener=fake, sleep=self.waits.append)

    def test_releases_and_filters(self):
        fake = FakeMB(
            {"Sia": [{"id": "sia", "name": "Sia", "score": 100}, {"id": "other", "name": "Sia Furler", "score": 95}]},
            {
                "sia": [
                    group(1, "Reasonable Woman", date="2024-05-03"),
                    group(2, "Gimme", kind="Single", date="2024-03"),
                    group(3, "Live at X", secondary=["Live"]),  # live: out
                    group(4, "Hits", secondary=["Compilation"]),  # compilation: out
                    group(5, "Undated", date=""),  # no date: out
                    group(6, "Broadcast", kind="Broadcast"),  # not album/ep/single: out
                ]
                + [group(100 + i, f"Single {i}", kind="Single", date="2020") for i in range(120)],  # two pages
            },
        )
        mb = self.mb(fake)
        self.assertEqual(mb.find_artist("Sia", []), "sia")
        got = mb.release_groups("sia")
        self.assertEqual(len(got), 122)
        self.assertEqual(
            got[0], {"mbid": "rg1", "title": "Reasonable Woman", "kind": "album", "released": "2024-05-03"}
        )
        self.assertEqual(got[1]["kind"], "single")
        self.assertEqual(sum(1 for p, _, _ in fake.requests if p.endswith("/release-group")), 2)
        for _, q, ua in fake.requests:
            self.assertEqual(q["fmt"], "json")
            self.assertEqual(ua, "tty.fm/test ( https://example )")
        # One request per second at most: waits between requests.
        self.assertTrue(self.waits and all(w <= 1.1 for w in self.waits))

    def test_namesakes_and_unknown(self):
        fake = FakeMB(
            {
                "Kassette": [
                    {"id": "k1", "name": "Kassette", "score": 100},
                    {"id": "k2", "name": "kassette", "score": 98},
                ],
                "Nobody": [{"id": "n", "name": "Nobody Else", "score": 70}],
            },
            {"k1": [group(1, "Other Band Album")], "k2": [group(2, "Cassette 92 (Deluxe)")]},
        )
        mb = self.mb(fake)
        self.assertEqual(mb.find_artist("Kassette", ["Cassette 92"]), "k2")  # the one with our album
        self.assertIsNone(mb.find_artist("Nobody", []))

    def test_backs_off_when_rate_limited(self):
        fake = FakeMB({"Sia": [{"id": "sia", "name": "Sia", "score": 100}]}, {}, fail_first=1)
        mb = self.mb(fake)
        self.assertEqual(mb.find_artist("Sia", []), "sia")
        self.assertIn(5, self.waits)

    def test_worker_sends_what_it_found(self):
        fake = FakeMB({"Sia": [{"id": "sia", "name": "Sia", "score": 100}]}, {"sia": [group(1, "Reasonable Woman")]})
        client = FakeClient(
            [
                {"artist_id": 1, "name": "Sia", "albums": []},
                {"artist_id": 2, "name": "Unknown Band", "albums": []},
                {"artist_id": 3, "name": "Tagged", "mbid": "sia", "albums": []},  # known mbid: no search
            ]
        )
        worker = ReleaseWorker(client, self.mb(fake))
        self.assertEqual(worker.run_once(), 3)
        self.assertEqual(client.saved[1]["mbid"], "sia")
        self.assertEqual(client.saved[1]["releases"][0]["title"], "Reasonable Woman")
        self.assertEqual(client.saved[2], {"mbid": None, "releases": []})
        searches = [q["query"] for p, q, _ in fake.requests if p.endswith("/artist")]
        self.assertEqual(searches, ['artist:"Sia"', 'artist:"Unknown Band"'])

    def test_title_key(self):
        self.assertEqual(title_key("25 (Deluxe Edition)"), "25")
        self.assertEqual(title_key("Beyoncé!"), "beyonce")
        self.assertEqual(title_key("(What's the Story)"), "what s the story")


if __name__ == "__main__":
    unittest.main()
