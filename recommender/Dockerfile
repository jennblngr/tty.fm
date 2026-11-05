# syntax=docker/dockerfile:1
# Audio analysis worker (phase 3). Essentia's wheel bundles its own decoders
# (ffmpeg libraries), so the image needs nothing beyond Python.
FROM python:3.13-slim-trixie
WORKDIR /app
COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt
COPY ttyfm_recommender ./ttyfm_recommender
ARG VERSION=dev
LABEL org.opencontainers.image.version=$VERSION

ENV PYTHONUNBUFFERED=1 \
    TTYFM_MUSIC_DIR=/music \
    TTYFM_STATE_DIR=/state \
    TTYFM_SERVER_URL=http://server:4533
VOLUME ["/state"]
ENTRYPOINT ["python", "-m", "ttyfm_recommender"]
