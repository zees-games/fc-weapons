#!/usr/bin/env bash
# Scope clips for the visual judge (see render_scope_clip.gd): tools/render_scope_clip.sh <out dir under the project> [gun]
# [gun] [clip]: one clip only. Needs a GPU window (xvfb is enough for the frames, the judge wants a GPU box in the log); writes <out>/<gun>/<clip>/NNNN.png frames (gpu.sh shot copies new PNGs back); tools/encode_scope_clip.sh makes the mp4s.
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=${1:?usage: tools/render_scope_clip.sh <out dir under the project> [gun] [clip]}; GUN=${2:-sniper}
xvfb-run -a -s "-screen 0 960x540x24" timeout 900 godot --path . --resolution 960x540 --fixed-fps 30 --script tools/render_scope_clip.gd -- "$OUT" "$GUN" "${3:-}" 2>&1 | grep -E "RESULT|ERROR|SCRIPT" | head -40
