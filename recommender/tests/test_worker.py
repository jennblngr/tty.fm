import os
import tempfile
import unittest

from tests import fakes
from ttyfm_recommender import worker


class FakeClient:
    def __init__(self, jobs):
        self.jobs = jobs
        self.reports = {}

    def queue(self, limit=20, analyzer=None):
        jobs, self.jobs = self.jobs[:limit], self.jobs[limit:]
        return jobs

    def report(self, track_id, report):
        self.reports[track_id] = report


class WorkerTest(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.mkdtemp()
        os.makedirs(os.path.join(self.dir, "a"))
        open(os.path.join(self.dir, "a", "song.flac"), "w").close()

    def test_resolve_stays_in_music_dir(self):
        self.assertEqual(
            worker.resolve(self.dir, "a/song.flac"), os.path.realpath(os.path.join(self.dir, "a/song.flac"))
        )
        with self.assertRaises(ValueError):
            worker.resolve(self.dir, "../etc/passwd")

    def test_isolation(self):
        self.assertEqual(worker.analyze_isolated("x", 10, fakes.ok)["bpm"], 120.0)
        self.assertEqual(worker.analyze_isolated("x", 10, fakes.fails), {"error": "ValueError: cannot decode"})
        self.assertEqual(worker.analyze_isolated("x", 10, fakes.crashes), {"error": "analyser crashed"})
        self.assertEqual(worker.analyze_isolated("x", 0.5, fakes.hangs), {"error": "timeout after 0 s"})

    def test_run_once_reports_every_job(self):
        client = FakeClient(
            [
                {"id": 1, "path": "a/song.flac", "file_mtime": 11, "duration_ms": 1},
                {"id": 2, "path": "../outside.flac", "file_mtime": 12, "duration_ms": 1},
            ]
        )
        w = worker.Worker(client, self.dir, "test/1", workers=2, timeout=10, analyze_fn=fakes.ok)
        self.assertEqual(w.run_once(), 2)
        self.assertEqual(w.run_once(), 0)
        one = client.reports[1]
        self.assertEqual((one["file_mtime"], one["analyzer"], one["bpm"]), (11, "test/1", 120.0))
        self.assertEqual(one["path_seen"], os.path.realpath(os.path.join(self.dir, "a/song.flac")))
        self.assertIn("outside the music folder", client.reports[2]["error"])


if __name__ == "__main__":
    unittest.main()
