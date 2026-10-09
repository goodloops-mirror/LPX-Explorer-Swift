#!/bin/bash
# Build the install disk image: the app plus a shortcut to /Applications to drag it onto.
#
#   scripts/make-dmg.sh [path/to/App.app] [out.dmg] [--dry-run]
#
# Signing / notarizing the image is scripts/sign-app.sh's job (package.sh runs both). --dry-run prints the commands only.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
APP="$HERE/../build/LPX Explorer.app"; OUT="$HERE/../dist/LPX-Explorer.dmg"; dry=0; n=0
for a in "$@"; do
  case "$a" in
    --dry-run) dry=1 ;;
    -*) echo "unknown option $a" >&2; exit 2 ;;
    *) n=$((n + 1)); if [ "$n" = 1 ]; then APP="$a"; else OUT="$a"; fi ;;
  esac
done
[ "$dry" = 1 ] || [ -d "$APP" ] || { echo "no app at $APP — build it first (scripts/make-app.sh)" >&2; exit 1; }

run() { echo "+ $*"; if [ "$dry" = 0 ]; then "$@"; fi; }

STAGE="${TMPDIR:-/tmp}/lpx-dmg-$$"
run mkdir -p "$STAGE" "$(dirname "$OUT")"
run ditto --norsrc --noextattr --noqtn "$APP" "$STAGE/$(basename "$APP")"      # a clean copy, no ._ files
run ln -s /Applications "$STAGE/Applications"
run rm -f "$OUT"
# Compressed, read-only image named like the app.
run hdiutil create -volname "LPX Explorer" -srcfolder "$STAGE" -format UDZO -fs HFS+ -ov "$OUT"
run rm -rf "$STAGE"
echo "done: $OUT$( [ "$dry" = 1 ] && echo ' (dry run: nothing was executed)')"
