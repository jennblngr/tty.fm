# syntax=docker/dockerfile:1

# --- build ------------------------------------------------------------------
FROM golang:1.27-trixie AS build
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
ARG VERSION=dev
# CGO is required by mattn/go-sqlite3; sqlite_fts5 enables full-text search.
RUN CGO_ENABLED=1 go build -tags sqlite_fts5 \
      -ldflags "-s -w -X ttyfm/internal/app.Version=${VERSION}" \
      -o /out/ttyfm ./cmd/ttyfm

# --- runtime ----------------------------------------------------------------
FROM debian:trixie-slim
RUN apt-get update \
 && apt-get install -y --no-install-recommends ffmpeg ca-certificates tzdata \
 && rm -rf /var/lib/apt/lists/*
COPY --from=build /out/ttyfm /usr/local/bin/ttyfm

ENV TTYFM_MUSIC_DIR=/music \
    TTYFM_DATA_DIR=/data \
    TTYFM_LISTEN=:4533
VOLUME ["/data"]
EXPOSE 4533
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s CMD ["ttyfm", "healthcheck"]
ENTRYPOINT ["ttyfm"]
