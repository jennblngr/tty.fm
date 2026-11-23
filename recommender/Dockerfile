# syntax=docker/dockerfile:1
# Recommender service: audio analysis, MusicBrainz and ListenBrainz lookups.
# Essentia's wheel bundles its own decoders (ffmpeg libraries) and
# TensorFlow, so the image needs nothing beyond Python.
FROM python:3.13-slim-trixie
WORKDIR /app
COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt
# The ML models (genre, mood, acousticness), checked against their sha256.
# models.py is standalone: copied alone, the layer survives code changes.
COPY ttyfm_recommender/models.py /tmp/models.py
RUN python /tmp/models.py /models && rm /tmp/models.py
COPY ttyfm_recommender ./ttyfm_recommender
ARG VERSION=dev
LABEL org.opencontainers.image.version=$VERSION

ENV PYTHONUNBUFFERED=1 \
    TTYFM_VERSION=$VERSION \
    TF_CPP_MIN_LOG_LEVEL=2 \
    TTYFM_MUSIC_DIR=/music \
    TTYFM_STATE_DIR=/state \
    TTYFM_MODELS_DIR=/models \
    TTYFM_SERVER_URL=http://server:4533
VOLUME ["/state"]
ENTRYPOINT ["python", "-m", "ttyfm_recommender"]
