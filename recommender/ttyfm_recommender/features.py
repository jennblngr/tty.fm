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


# Discogs' top-level genres in French (styles keep their Discogs names).
GENRE_NAMES = {
    "Blues": "blues",
    "Brass & Military": "fanfare",
    "Children's": "enfants",
    "Classical": "classique",
    "Electronic": "électro",
    "Folk, World, & Country": "folk / world",
    "Funk / Soul": "funk / soul",
    "Hip Hop": "hip-hop",
    "Jazz": "jazz",
    "Latin": "latino",
    "Non-Music": "non musical",
    "Pop": "pop",
    "Reggae": "reggae",
    "Rock": "rock",
    "Stage & Screen": "musique de film",
}


def genre_shares(scores, labels: list[str]) -> list[dict]:
    """Genre and sub-genre from the mean activations of the Discogs 400
    styles (labels "Genre---Style"): the genre whose styles weigh most, then
    its strongest style, each as a share of the total activation."""
    total = float(sum(scores))
    if not total > 0:
        return []
    by_genre: dict[str, float] = {}
    best: dict[str, tuple[float, str]] = {}
    for score, label in zip(scores, labels, strict=True):
        genre, _, style = label.partition("---")
        score = float(score)
        by_genre[genre] = by_genre.get(genre, 0.0) + score
        if score > best.get(genre, (-1.0, ""))[0]:
            best[genre] = (score, style)
    genre = max(by_genre, key=by_genre.get)
    style_score, style = best[genre]
    out = [{"name": GENRE_NAMES.get(genre, genre.lower()), "share": round(clamp01(by_genre[genre] / total), 3)}]
    if style:
        out.append({"name": style.lower(), "share": round(clamp01(style_score / total), 3)})
    return out


def mood_label(probabilities: dict[str, float], threshold: float = 0.5, most: int = 2) -> str | None:
    """The moods the classifiers are confident about, strongest first,
    joined like the design ("calme · mélancolique"); None if there is none."""
    picked = sorted((p, name) for name, p in probabilities.items() if p >= threshold)
    return " · ".join(name for _, name in reversed(picked[-most:])) or None


def mean_embedding(windows, decimals: int = 5) -> list[float] | None:
    """The track's embedding for the similarity search: the mean of the
    per-window embeddings, scaled to unit length (the server compares
    directions, by cosine distance) and rounded to keep the report small.
    None if there is nothing to average or no direction."""
    import numpy as np

    windows = np.asarray(windows, dtype=np.float64)
    if windows.ndim != 2 or len(windows) == 0:
        return None
    mean = windows.mean(axis=0)
    norm = float(np.linalg.norm(mean))
    if not math.isfinite(norm) or norm == 0:
        return None
    return [round(float(x), decimals) for x in mean / norm]
