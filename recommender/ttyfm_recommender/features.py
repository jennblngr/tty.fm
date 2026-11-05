"""Pure helpers that turn raw Essentia measurements into the 0..1 values
the API stores. Kept free of Essentia so they can be tested anywhere."""

from __future__ import annotations

import math

# Essentia spells some keys with flats (Eb, Ab, Bb); the server accepts
# both, but sharps keep the reports uniform.
_SHARPS = {"Db": "C#", "Eb": "D#", "Gb": "F#", "Ab": "G#", "Bb": "A#"}


def normalize_key(key: str) -> str:
    return _SHARPS.get(key, key)


def clamp01(x: float) -> float:
    if math.isnan(x):
        return 0.0
    return min(1.0, max(0.0, x))


def scale(x: float, lo: float, hi: float) -> float:
    """Maps lo..hi linearly to 0..1, clamped."""
    return clamp01((x - lo) / (hi - lo))


def fold_bpm(bpm: float, lo: float = 60.0, hi: float = 200.0) -> float:
    """Brings a tempo estimate into lo..hi by halving / doubling: beat
    trackers often lock on half or twice the perceived tempo at the edges."""
    if bpm <= 0 or math.isnan(bpm):
        return bpm
    while bpm < lo:
        bpm *= 2
    while bpm > hi:
        bpm /= 2
    return bpm


def danceability(raw: float) -> float:
    """Essentia's Danceability (detrended fluctuation analysis) is roughly
    0..3, most music landing in 0.8..2."""
    return scale(raw, 0.5, 2.5)


def energy(lufs: float, onset_rate: float, centroid_hz: float) -> float:
    """A perceptual energy estimate: loud, busy and bright tracks score high.

    - integrated loudness, -30 LUFS (quiet, dynamic) .. -6 LUFS (brickwalled);
    - onset rate, 0 .. 6 onsets per second (sparse .. dense);
    - mean spectral centroid, 500 .. 3500 Hz (dark .. bright).
    """
    return round(
        0.5 * scale(lufs, -30, -6) + 0.3 * scale(onset_rate, 0, 6) + 0.2 * scale(centroid_hz, 500, 3500),
        3,
    )
