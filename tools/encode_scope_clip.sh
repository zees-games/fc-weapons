#!/usr/bin/env bash
# Encodes the frames tools/render_scope_clip.sh left into <out>/<gun>/<clip>.mp4 (run where the frames landed, after the GPU render).
# tools/encode_scope_clip.sh <out dir under the project> [gun]
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=${1:?usage: tools/encode_scope_clip.sh <out dir under the project> [gun]}; GUN=${2:-sniper}
for d in "$OUT/$GUN"/*/; do
  ffmpeg -y -loglevel error -framerate 30 -i "$d/%04d.png" -c:v libx264 -pix_fmt yuv420p -crf 18 "${d%/}.mp4"
  rm -rf "$d"
done
ls "$OUT/$GUN"
