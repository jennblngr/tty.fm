"""Audio analysis of one file with Essentia's classic algorithms: tempo,
key, loudness (EBU R128), energy and danceability.

Genre, mood and acousticness need Essentia's TensorFlow models; they are
not computed yet and left out of the report.
"""

from __future__ import annotations

import numpy as np

from . import features

SAMPLE_RATE = 44100  # OnsetRate and the rhythm extractor expect 44.1 kHz
MAX_SECONDS = 15 * 60  # longer files (DJ mixes, audiobooks) are cut


def analyzer_name() -> str:
    import essentia

    return f"essentia-{essentia.__version__}/1"


def analyze(path: str) -> dict:
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
