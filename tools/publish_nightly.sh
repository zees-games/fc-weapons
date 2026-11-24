#!/bin/bash
# Publishes the attachments to Nightly as assets of their own, linked to the guns they fit with their mount slot and position.
# The numbers are read by tools/export_nightly_attachments.gd from the game's tables (AwAttachmentSockets, AwAttachmentPack, AwWeaponArt).
#   NIGHTLY_URL=http://panel NIGHTLY_TOKEN=... tools/publish_nightly.sh [--dry-run]
# The glbs land in build/nightly/ under this pack; Nightly reads them from there, so this checkout must be a registered asset source of the
# panel's host (the same root the weapons are listed from). Without NIGHTLY_URL it only exports.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$HERE/build/nightly"
# The export writes into this checkout, so it must run here and not be handed to the build VM.
GPU_OFFLOAD=0 HEAVY_PIN_LOCAL=1 heavy -- timeout 300 godot --headless --path "$HERE" --script res://tools/export_nightly_attachments.gd -- "$OUT" build/nightly 2>&1 | grep -E "export_nightly|ERROR|SCRIPT" || true
[ -s "$OUT/attachments.json" ] || { echo "publish_nightly: export wrote nothing" >&2; exit 1; }
[ "${1:-}" = "--dry-run" ] && { echo "publish_nightly: dry run, $OUT/attachments.json"; exit 0; }
[ -n "${NIGHTLY_URL:-}" ] || { echo "publish_nightly: exported to $OUT (set NIGHTLY_URL and NIGHTLY_TOKEN to publish)"; exit 0; }
curl -fsS -X POST -H "Authorization: Bearer ${NIGHTLY_TOKEN:?NIGHTLY_TOKEN is needed with NIGHTLY_URL}" --data-binary "@$OUT/attachments.json" "${NIGHTLY_URL%/}/api/assets/ingest"
echo
