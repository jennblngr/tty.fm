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


if __name__ == "__main__":
    unittest.main()
