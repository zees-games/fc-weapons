#!/bin/bash
# Publishes this pack with addons/fc_weapons, the code a host mounts from it as an overlay, as gamemann/fc-weapons:
# the site keeps gamemann/fc-weapons retired (moved to fc-weapons) and refuses a publish under it.
#   GS_SITE=https://tmcdev.net tools/publish.sh VERSION --lock /tmp/aw-lock.json --token-file ~/.config/gs/creator-token-dev [--dry-run]
# Then it publishes the attachments and their links to Nightly (tools/publish_nightly.sh: exports only unless NIGHTLY_URL and NIGHTLY_TOKEN are set).
# Give --lock a file outside the repo: content.lock.json here pins the art store, not this pack.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
V=${1:?usage: tools/publish.sh VERSION [publish_pack.sh flags]}; shift
# Every addon folder but addons/fc_weapons stays out, by folder name, so a copy with links resolved (heavy's staging box) packs the same.
EX=(); for d in "$HERE"/addons/*/; do n="$(basename "$d")"; [ "$n" = fc_weapons ] || EX+=(--exclude-dir "$n"); done
# assets-src holds the raw recordings the cues and shots are cut from (22 MB, licence unconfirmed): never packed, never shipped.
EX+=(--exclude-dir assets-src)
"$HERE/../gs-cloud/tools/publish_pack.sh" publish --source "$HERE" --id fc-weapons --version "$V" "${EX[@]}" "$@"
# A --dry-run of the pack is a dry run of the attachments too.
NA=(); for a in "$@"; do [ "$a" = "--dry-run" ] && NA=(--dry-run); done
"$HERE/tools/publish_nightly.sh" "${NA[@]}"
