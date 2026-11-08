"""Essentia's TensorFlow models (genre, mood, acousticness): the files, where
to download them and their checksums.

    python -m ttyfm_recommender.models /models

downloads the missing ones into /models and checks them. The Docker image
does it at build time; without the models, the analysis skips these fields.
"""

from __future__ import annotations

import hashlib
import os
import sys
import tempfile
import urllib.request

BASE_URL = "https://essentia.upf.edu/models"

# The embedding model and the heads trained on its embeddings.
EMBEDDINGS = "discogs-effnet-bs64-1.pb"
GENRES = "genre_discogs400-discogs-effnet-1"
# Mood heads: the positive class and its French label (the app shows them as is).
MOODS = {
    "happy": "joyeux",
    "sad": "mélancolique",
    "relaxed": "calme",
    "aggressive": "agressif",
    "party": "festif",
}
ACOUSTIC = "mood_acoustic-discogs-effnet-1"


def mood_model(name: str) -> str:
    return f"mood_{name}-discogs-effnet-1"


# file -> (path under BASE_URL, sha256)
FILES = {
    EMBEDDINGS: (
        "feature-extractors/discogs-effnet",
        "3ed9af50d5367c0b9c795b294b00e7599e4943244f4cbd376869f3bfc87721b1",
    ),
    f"{GENRES}.pb": (
        "classification-heads/genre_discogs400",
        "3885ba078a35249af94b8e5e4247689afac40deca4401a4bc888daf5a579c01c",
    ),
    f"{GENRES}.json": (
        "classification-heads/genre_discogs400",
        "2d367319d9b782ffa10f69abf0e805b3ac4e10899025e5bdbaceda3919b243e0",
    ),
}
_HEADS = {
    "acoustic": (
        "96a48d403f52fe9047214437fe396dd2f46699da765c911cd6dfbd456a20f733",
        "45f61055d1d87d5e7f8a413b06b57eca20c3af1a23cf8912e0d916422e5207e1",
    ),
    "aggressive": (
        "7705284e3a67f23f04d3f2fd75e18a82c0e70db8875b7b6f7061f2432de80858",
        "81773e95d78db1b93283d73b2d06344d1ff79685b57d9428a40d47fdfcf537b8",
    ),
    "happy": (
        "de322aee7f4da29ecbd149c86e7964bd6fabe41ca85698a0be40a39d49e88633",
        "ed4601bc396b23367d29cf45aa327366cdfdbd3e2baeb7a3f7893237f1ffd9e6",
    ),
    "party": (
        "bbd773a27002978179dd6fc5ffb75b7c41e6a7e412b5c5254d51a025e5b9373e",
        "a7f15c6e05db7c3e9226646a87162ebb9cc00aea8bdbbc910aedafa7f4a8fdfb",
    ),
    "relaxed": (
        "2c5aa6666b58fe80429a2dc677a135e9995922889b5a399af87d1c15f0ebb71d",
        "86c0fe1c2c6d49bf08537bc2d3a602204feaede011ed119c1fc6c36270f60e6a",
    ),
    "sad": (
        "4865cba49968b6ec295db3e8af6b4a7bb506b1a646628b9f07ee9910d52df82c",
        "7f2c00099ad8255af33e43ab77d1ac2c86a1dd9f46d3e5ea2a9a52246f5033d9",
    ),
}
for _name, (_pb, _json) in _HEADS.items():
    FILES[f"{mood_model(_name)}.pb"] = (f"classification-heads/mood_{_name}", _pb)
    FILES[f"{mood_model(_name)}.json"] = (f"classification-heads/mood_{_name}", _json)

# Bumped when the files or the way their output is read change: tracks
# analysed with another version are analysed again.
# 2: the report carries the mean embedding (similar tracks).
VERSION = "discogs-effnet-2"


def _sha256(path: str) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def available(models_dir: str | None) -> bool:
    """True if every model file is in models_dir (checked by size only:
    checksums are verified once, at download)."""
    if not models_dir:
        return False
    return all(os.path.isfile(os.path.join(models_dir, name)) for name in FILES)


def download(models_dir: str, base_url: str = BASE_URL) -> list[str]:
    """Downloads the files missing from models_dir; returns their names.
    Raises if a checksum does not match (nothing is left behind then)."""
    os.makedirs(models_dir, exist_ok=True)
    fetched = []
    for name, (sub, digest) in FILES.items():
        dest = os.path.join(models_dir, name)
        if os.path.isfile(dest) and _sha256(dest) == digest:
            continue
        fd, tmp = tempfile.mkstemp(dir=models_dir, prefix=".part-")
        try:
            with os.fdopen(fd, "wb") as out, urllib.request.urlopen(f"{base_url}/{sub}/{name}", timeout=60) as r:
                while chunk := r.read(1 << 20):
                    out.write(chunk)
            if (got := _sha256(tmp)) != digest:
                raise ValueError(f"{name}: sha256 {got}, expected {digest}")
            os.chmod(tmp, 0o644)  # mkstemp makes it 0600; the worker may run as another user
            os.replace(tmp, dest)
        finally:
            if os.path.exists(tmp):
                os.remove(tmp)
        fetched.append(name)
    return fetched


def main(argv: list[str]) -> int:
    if len(argv) != 1:
        print("usage: python -m ttyfm_recommender.models DIR", file=sys.stderr)
        return 2
    for name in download(argv[0]):
        print(f"downloaded {name}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
