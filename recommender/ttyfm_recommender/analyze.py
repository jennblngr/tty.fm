"""Audio analysis of one file with Essentia's classic algorithms: tempo,
key, loudness (EBU R128), energy and danceability.

With Essentia's TensorFlow models (see models.py), also genre and sub-genre,
mood and acousticness; without them these fields are left out of the report.
"""

from __future__ import annotations

import json
import os

import numpy as np

from . import features, models

SAMPLE_RATE = 44100  # OnsetRate and the rhythm extractor expect 44.1 kHz
MODEL_RATE = 16000  # the Discogs EffNet models
MAX_SECONDS = 15 * 60  # longer files (DJ mixes, audiobooks) are cut


def analyzer_name(models_dir: str | None = None) -> str:
    """Stored with each analysis: the server queues the tracks analysed by
    another name again, so it changes when the results would."""
    import essentia

    name = f"essentia-{essentia.__version__}/1"
    if models.available(models_dir):
        name += f"+{models.VERSION}"
    return name


def analyze(path: str, models_dir: str | None = None) -> dict:
    """Returns the report fields (see the API's AnalysisReport) for path.
    Raises on files Essentia cannot decode."""
    import essentia
    import essentia.standard as es

    essentia.log.infoActive = False
    stereo, sr, channels, *_ = es.AudioLoader(filename=path)()
    if stereo.shape[0] == 0:
        raise ValueError("empty audio")
    stereo = stereo[: int(MAX_SECONDS * sr)]

    # Loudness on the original signal (EBU R128 handles any rate).
    _, _, lufs, lra = es.LoudnessEBUR128(sampleRate=sr)(stereo)

    mono = es.MonoMixer()(stereo, channels)
    if sr != SAMPLE_RATE:
        mono = es.Resample(inputSampleRate=sr, outputSampleRate=SAMPLE_RATE)(mono)
    mono = np.ascontiguousarray(mono, dtype=np.float32)

    bpm, _ticks, _confidence, _estimates, _intervals = es.RhythmExtractor2013(method="multifeature")(mono)
    key, scale, strength = es.KeyExtractor(profileType="bgate", sampleRate=SAMPLE_RATE)(mono)
    dance, _ = es.Danceability(sampleRate=SAMPLE_RATE)(mono)
    _, onset_rate = es.OnsetRate()(mono)
    centroid = _mean_centroid(es, mono)

    # Silence yields -inf loudness: leave out what the API would refuse.
    lufs, lra = float(lufs), float(lra)
    if not (np.isfinite(lufs) and -70 <= lufs <= 10):
        lufs = None
    report: dict = {
        "energy": features.energy(lufs if lufs is not None else -70.0, float(onset_rate), centroid),
        "danceability": round(features.danceability(float(dance)), 3),
    }
    if lufs is not None:
        report["loudness_lufs"] = round(lufs, 2)
    if np.isfinite(lra) and 0 <= lra <= 100:
        report["loudness_range"] = round(lra, 2)
    bpm = features.fold_bpm(float(bpm))
    if 20 <= bpm <= 300:
        report["bpm"] = round(bpm, 1)
    if key and scale in ("major", "minor"):
        report["key"] = features.normalize_key(key)
        report["scale"] = scale
        report["key_strength"] = round(features.clamp01(float(strength)), 3)
    if models.available(models_dir):
        audio = es.Resample(inputSampleRate=SAMPLE_RATE, outputSampleRate=MODEL_RATE)(mono)
        report.update(_classify(es, models_dir, audio))
    return report


def _classify(es, models_dir: str, audio: np.ndarray) -> dict:
    """Genre, mood and acousticness from the Discogs EffNet embeddings of
    16 kHz mono audio, averaged over the track."""

    def path(name: str) -> str:
        return os.path.join(models_dir, name)

    embeddings = es.TensorflowPredictEffnetDiscogs(graphFilename=path(models.EMBEDDINGS), output="PartitionedCall:1")(
        audio
    )
    if len(embeddings) == 0:  # shorter than one patch (~2 s)
        return {}

    def head(name: str, **kw) -> np.ndarray:
        out = es.TensorflowPredict2D(graphFilename=path(f"{name}.pb"), **kw)(embeddings)
        return np.mean(out, axis=0)

    def positive(name: str, label: str) -> float:
        """Probability of the class named label, from a two-class head."""
        with open(path(f"{name}.json")) as f:
            classes = json.load(f)["classes"]
        return float(head(name, output="model/Softmax")[classes.index(label)])

    with open(path(f"{models.GENRES}.json")) as f:
        labels = json.load(f)["classes"]
    scores = head(models.GENRES, input="serving_default_model_Placeholder", output="PartitionedCall:0")
    report: dict = {
        "acousticness": round(features.clamp01(positive(models.ACOUSTIC, "acoustic")), 3),
    }
    if genres := features.genre_shares(scores, labels):
        report["genres"] = genres
    moods = {fr: positive(models.mood_model(name), name) for name, fr in models.MOODS.items()}
    if mood := features.mood_label(moods):
        report["mood"] = mood
    return report


def _mean_centroid(es, mono: np.ndarray) -> float:
    """Mean spectral centroid in Hz, on frames every ~0.2 s (cheap)."""
    window = es.Windowing(type="hann")
    spectrum = es.Spectrum()
    centroid = es.Centroid(range=SAMPLE_RATE / 2)
    values = [
        centroid(spectrum(window(frame)))
        for frame in es.FrameGenerator(mono, frameSize=2048, hopSize=8192, startFromZero=True)
    ]
    return float(np.mean(values)) if values else 0.0
