#!/bin/bash
# Version of the working tree, derived from git tags (single source of truth).
#   scripts/version.sh            -> 0.1.0           (latest release tag, v-prefix stripped)
#   scripts/version.sh --describe -> 0.1.0-3-gabc123[-dirty]   (what exactly is built)
#   scripts/version.sh --build    -> commit count (CFBundleVersion)
# Only tags of the SwiftUI app count (v0.1.0 and up); the legacy Tauri tags (v0.0.x) are ignored.
set -euo pipefail
cd "$(dirname "$0")/.."
# Run `git` against $LPX_VERSION_REPO when set (used by the release test).
[ -n "${LPX_VERSION_REPO:-}" ] && cd "$LPX_VERSION_REPO"
# Nearest release tag reachable from HEAD (so a checkout of an old tag reports that tag, not the newest one).
latest_tag() { git describe --tags --abbrev=0 --match 'v[0-9]*' --exclude 'v0.0.*' 2>/dev/null || true; }
tag="$(latest_tag)"
case "${1:-}" in
  --build) git rev-list --count HEAD 2>/dev/null || echo 1 ;;
  --describe)
    if [ -n "$tag" ]; then git describe --tags --match "$tag" --dirty 2>/dev/null || echo "${tag#v}"
    else echo "0.0.0-$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"; fi ;;
  *) if [ -n "$tag" ]; then echo "${tag#v}"; else echo "0.0.0"; fi ;;
esac
