#!/usr/bin/env bash
# Generates a tiny demo library (3 albums × 4 tracks of 40 s, with covers)
# used by the client's end-to-end test. Requires ffmpeg.
set -euo pipefail
D="${1:-data/dev-music}"
rm -rf "$D"
i=0
for spec in "Nova Lines|Midnight Drive|2021|9b59b6" "Les Rivages|Marée Haute|2019|1abc9c" "Quartz Trio|Blue Hours|2023|e67e22"; do
  IFS="|" read -r artist album year color <<< "$spec"
  mkdir -p "$D/$artist/$album"
  ffmpeg -y -loglevel error -f lavfi -i "color=c=0x${color}:s=800x800" -frames:v 1 "$D/$artist/$album/cover.jpg"
  for n in 1 2 3 4; do
    i=$((i + 1))
    ffmpeg -y -loglevel error -f lavfi -i "sine=frequency=$((220 + i * 40)):duration=40" -af "volume=0.3" \
      -metadata title="Track $n of $album" -metadata artist="$artist" -metadata album="$album" \
      -metadata date="$year" -metadata track="$n" "$D/$artist/$album/0$n.flac"
  done
done
echo "Demo library written to $D"
