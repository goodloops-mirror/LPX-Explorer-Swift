#!/bin/bash
# Build the app and package it for distribution as a disk image: dist/LPX-Explorer-<version>.dmg
#   scripts/package.sh            package the current checkout
#   scripts/package.sh v0.1.0     package exactly that release (built in a temporary worktree)
# Without a signing identity the app is only ad-hoc signed: on another Mac Gatekeeper blocks the first launch
# (right-click → Open, or `xattr -dr com.apple.quarantine "LPX Explorer.app"`).
# With LPX_SIGN_IDENTITY set it is signed with your Developer ID, and with LPX_NOTARY_PROFILE as well it is notarized and
# stapled (scripts/sign-app.sh, docs/SIGNING.md) — then the disk image opens everywhere without a warning.
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
# 1. Sign the app (and notarize + staple it when a notary profile is set), 2. put it in a disk image, 3. sign (and notarize +
# staple) the image: the image is what users download.
if [ -n "${LPX_SIGN_IDENTITY:-}" ]; then
  "$ROOT/scripts/sign-app.sh" "$src/build/LPX Explorer.app" ${LPX_NOTARY_PROFILE:+--notarize}
fi
dmgPath="$ROOT/dist/LPX-Explorer-$name.dmg"
"$ROOT/scripts/make-dmg.sh" "$src/build/LPX Explorer.app" "$dmgPath"
if [ -n "${LPX_SIGN_IDENTITY:-}" ]; then
  "$ROOT/scripts/sign-app.sh" "$dmgPath" ${LPX_NOTARY_PROFILE:+--notarize}
fi
echo "Packaged: dist/$(basename "$dmgPath") ($(du -h "$dmgPath" | cut -f1))"
