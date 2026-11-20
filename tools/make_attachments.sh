#!/usr/bin/env bash
# Rebuilds the attachment models in place: tools/make_attachments.sh [<id>...]  (see make_attachments.gd)
set -euo pipefail
cd "$(dirname "$0")/.."
if [ $# -gt 0 ]; then set -- -- "$@"; fi
timeout 300 godot --headless --path . --script res://tools/make_attachments.gd "$@" 2>&1 | grep -E "make_attachments|ERROR|SCRIPT"
