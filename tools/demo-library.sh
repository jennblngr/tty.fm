#!/usr/bin/env bash
# Generates a tiny demo library (3 albums × 4 tracks of 40 s, with covers,
# genres and one synced .lrc) used by the client's end-to-end test.
# Requires ffmpeg.
set -euo pipefail
D="${1:-data/dev-music}"
rm -rf "$D"
i=0
for spec in "Nova Lines|Midnight Drive|2021|9b59b6|Electro" "Les Rivages|Marée Haute|2019|1abc9c|Pop" "Quartz Trio|Blue Hours|2023|e67e22|Jazz"; do
  IFS="|" read -r artist album year color genre <<< "$spec"
  mkdir -p "$D/$artist/$album"
  ffmpeg -y -loglevel error -f lavfi -i "color=c=0x${color}:s=800x800" -frames:v 1 "$D/$artist/$album/cover.jpg"
  for n in 1 2 3 4; do
    i=$((i + 1))
    ffmpeg -y -loglevel error -f lavfi -i "sine=frequency=$((220 + i * 40)):duration=40" -af "volume=0.3" \
      -metadata title="Track $n of $album" -metadata artist="$artist" -metadata album="$album" \
      -metadata date="$year" -metadata genre="$genre" -metadata track="$n" "$D/$artist/$album/0$n.flac"
  done
done
printf '[00:00.50]First line of Blue Hours\n[00:03.00]Second line\n[00:06.00]Third line\n' \
  > "$D/Quartz Trio/Blue Hours/01.lrc"
echo "Demo library written to $D"
