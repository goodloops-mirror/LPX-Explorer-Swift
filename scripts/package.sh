#!/bin/bash
# Build the app and zip it for distribution: dist/LPX-Explorer-<version>.zip
#   scripts/package.sh            package the current checkout
#   scripts/package.sh v0.1.0     package exactly that release (built in a temporary worktree)
# The app is ad-hoc signed, not notarized: on another Mac Gatekeeper blocks the first launch
# (right-click → Open, or `xattr -dr com.apple.quarantine "LPX Explorer.app"`).
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
mkdir -p dist
tag="${1:-}"
src="$ROOT"
if [ -n "$tag" ]; then
  git rev-parse -q --verify "refs/tags/$tag" >/dev/null || { echo "no such tag $tag" >&2; exit 1; }
  src="$(mktemp -d)/src"
  git worktree add -q --detach "$src" "$tag"
  trap 'git -C "$ROOT" worktree remove --force "$src" >/dev/null 2>&1 || true' EXIT
fi
LPX_APP_SRC="$src" "$ROOT/scripts/make-app.sh"
name="$(LPX_VERSION_REPO="$src" "$ROOT/scripts/version.sh" --describe)"
cd "$src"
zip="$ROOT/dist/LPX-Explorer-$name.zip"
rm -f "$zip"
ditto -c -k --keepParent "build/LPX Explorer.app" "$zip"
echo "Packaged: dist/$(basename "$zip") ($(du -h "$zip" | cut -f1))"
