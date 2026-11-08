import math
import unittest

from ttyfm_recommender import features


class FeaturesTest(unittest.TestCase):
    def test_fold_bpm(self):
        self.assertEqual(features.fold_bpm(62), 62)
        self.assertEqual(features.fold_bpm(45), 90)
        self.assertEqual(features.fold_bpm(250), 125)
        self.assertEqual(features.fold_bpm(0), 0)

    def test_scale_and_clamp(self):
        self.assertEqual(features.scale(-18, -30, -6), 0.5)
        self.assertEqual(features.scale(0, -30, -6), 1)
        self.assertEqual(features.scale(-50, -30, -6), 0)
        self.assertEqual(features.clamp01(math.nan), 0)

    def test_energy_orders_tracks(self):
        quiet = features.energy(-28, 0.5, 800)
        loud = features.energy(-7, 5, 3000)
        self.assertLess(quiet, 0.2)
        self.assertGreater(loud, 0.8)
        self.assertTrue(0 <= features.energy(-70, 0, 0) <= features.energy(5, 100, 20000) <= 1)

    def test_keys_use_sharps(self):
        self.assertEqual(features.normalize_key("Eb"), "D#")
        self.assertEqual(features.normalize_key("A"), "A")

    def test_genre_shares(self):
        labels = ["Electronic---Synthwave", "Electronic---Techno", "Rock---Indie Rock", "Hip Hop---Trap"]
        # Rock has the strongest style, but Electronic weighs more overall.
        shares = features.genre_shares([0.3, 0.2, 0.4, 0.1], labels)
        self.assertEqual(shares, [{"name": "électro", "share": 0.5}, {"name": "synthwave", "share": 0.3}])
        self.assertEqual(features.genre_shares([0, 0, 0, 0], labels), [])
        self.assertEqual(features.genre_shares([1.0], ["Unknown---X"])[0]["name"], "unknown")

    def test_mood_label(self):
        self.assertEqual(
            features.mood_label({"calme": 0.7, "mélancolique": 0.9, "festif": 0.6}), "mélancolique · calme"
        )
        self.assertEqual(features.mood_label({"calme": 0.7, "festif": 0.2}), "calme")
        self.assertIsNone(features.mood_label({"calme": 0.4}))

    def test_mean_embedding(self):
        e = features.mean_embedding([[3.0, 0.0, 1.0], [3.0, 8.0, -1.0]])
        self.assertEqual(e, [0.6, 0.8, 0.0])  # mean (3, 4, 0), unit length
        self.assertIsNone(features.mean_embedding([]))
        self.assertIsNone(features.mean_embedding([[1.0, 0.0], [-1.0, 0.0]]))
        self.assertIsNone(features.mean_embedding([[math.nan, 1.0]]))


if __name__ == "__main__":
    unittest.main()
