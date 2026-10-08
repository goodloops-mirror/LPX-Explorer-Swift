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
latest_tag() { git tag --list 'v[0-9]*' | grep -Ev '^v0\.0\.' | sort -t. -k1.2,1n -k2,2n -k3,3n | tail -1 || true; }
tag="$(latest_tag)"
case "${1:-}" in
  --build) git rev-list --count HEAD 2>/dev/null || echo 1 ;;
  --describe)
    if [ -n "$tag" ]; then git describe --tags --match "$tag" --dirty 2>/dev/null || echo "${tag#v}"
    else echo "0.0.0-$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"; fi ;;
  *) if [ -n "$tag" ]; then echo "${tag#v}"; else echo "0.0.0"; fi ;;
esac
