#!/usr/bin/env bash
# Close-up sheet of the attachment models alone: tools/render_attach_models.sh <out.png under the project> <id>...  (see render_attach_models.gd)
set -euo pipefail
cd "$(dirname "$0")/.."
out=$1; shift
xvfb-run -a -s "-screen 0 1280x800x24" timeout 600 godot --path . --resolution 640x400 --script tools/render_attach_models.gd -- "$out" "$@" 2>&1 | grep -E "RESULT|ERROR|SCRIPT" | head -40
