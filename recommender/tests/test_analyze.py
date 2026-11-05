"""End-to-end analysis of a synthetic file: a 124 bpm kick over an A minor
chord. Skipped where Essentia is not installed."""

import os
import tempfile
import unittest
import wave

try:
    import essentia  # noqa: F401
    import numpy as np
except ImportError:  # pragma: no cover
    np = None


def write_test_wav(path, bpm=124.0, seconds=30, sr=44100):
    t = np.arange(int(sr * seconds)) / sr
    pad = sum(np.sin(2 * np.pi * f * t) for f in (220.0, 261.63, 329.63, 440.0)) * 0.08
    kick = np.zeros_like(t)
    n = int(0.12 * sr)
    env = np.exp(-np.arange(n) / sr * 30) * np.sin(2 * np.pi * 60 * np.arange(n) / sr) * 0.6
    for beat in np.arange(0, seconds, 60 / bpm):
        i = int(beat * sr)
        seg = kick[i : i + n]
        seg += env[: len(seg)]
    x = np.clip(pad + kick, -1, 1)
    with wave.open(path, "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(sr)
        w.writeframes((np.stack([x, x], 1) * 32767).astype("<i2").tobytes())


@unittest.skipIf(np is None, "essentia not installed")
class AnalyzeTest(unittest.TestCase):
    def test_synthetic_track(self):
        from ttyfm_recommender.analyze import analyze, analyzer_name

        path = os.path.join(tempfile.mkdtemp(), "t.wav")
        write_test_wav(path)
        r = analyze(path)
        self.assertAlmostEqual(r["bpm"], 124, delta=1)
        self.assertEqual((r["key"], r["scale"]), ("A", "minor"))
        self.assertTrue(-30 < r["loudness_lufs"] < -5)
        for k in ("energy", "danceability", "key_strength"):
            self.assertTrue(0 <= r[k] <= 1, k)
        self.assertTrue(analyzer_name().startswith("essentia-"))

    def test_undecodable_file(self):
        from ttyfm_recommender.analyze import analyze

        path = os.path.join(tempfile.mkdtemp(), "bad.flac")
        with open(path, "wb") as f:
            f.write(b"not audio at all")
        with self.assertRaises(RuntimeError):
            analyze(path)


if __name__ == "__main__":
    unittest.main()
