import functools
import hashlib
import os
import tempfile
import threading
import unittest
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from unittest import mock

from ttyfm_recommender import models


class QuietHandler(SimpleHTTPRequestHandler):
    def log_message(self, *args):
        pass


class ModelsTest(unittest.TestCase):
    def setUp(self):
        # A fake model site: two small files laid out like essentia.upf.edu.
        self.site = tempfile.mkdtemp()
        self.files = {}
        for name, sub, body in (("a.pb", "x/a", b"model"), ("a.json", "x/a", b'{"classes": []}')):
            os.makedirs(os.path.join(self.site, sub), exist_ok=True)
            with open(os.path.join(self.site, sub, name), "wb") as f:
                f.write(body)
            self.files[name] = (sub, hashlib.sha256(body).hexdigest())
        handler = functools.partial(QuietHandler, directory=self.site)
        self.srv = ThreadingHTTPServer(("127.0.0.1", 0), handler)
        threading.Thread(target=self.srv.serve_forever, daemon=True).start()
        self.url = f"http://127.0.0.1:{self.srv.server_port}"

    def tearDown(self):
        self.srv.shutdown()
        self.srv.server_close()

    def test_download_checks_and_skips(self):
        dest = tempfile.mkdtemp()
        with mock.patch.dict(models.FILES, self.files, clear=True):
            self.assertFalse(models.available(dest))
            self.assertEqual(sorted(models.download(dest, self.url)), ["a.json", "a.pb"])
            self.assertTrue(models.available(dest))
            self.assertEqual(os.stat(os.path.join(dest, "a.pb")).st_mode & 0o777, 0o644)
            self.assertEqual(models.download(dest, self.url), [])

    def test_bad_checksum_leaves_nothing(self):
        dest = tempfile.mkdtemp()
        with mock.patch.dict(models.FILES, {"a.pb": ("x/a", "0" * 64)}, clear=True):
            with self.assertRaises(ValueError):
                models.download(dest, self.url)
        self.assertEqual(os.listdir(dest), [])

    def test_manifest(self):
        self.assertFalse(models.available(None))
        self.assertIn(models.EMBEDDINGS, models.FILES)
        for name in models.MOODS:
            self.assertIn(models.mood_model(name) + ".pb", models.FILES)
        self.assertTrue(all(len(digest) == 64 for _, digest in models.FILES.values()))


if __name__ == "__main__":
    unittest.main()
