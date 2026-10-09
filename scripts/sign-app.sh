#!/bin/bash
# Sign the built app — or, when given a .dmg, the disk image — with a Developer ID certificate and (optionally) notarize and
# staple it, so that Gatekeeper opens it on other Macs without a warning. See docs/SIGNING.md for the one-time setup.
#
#   scripts/sign-app.sh [path/to/App.app | path/to/Image.dmg] [--notarize] [--dry-run]
#
# Environment:
#   LPX_SIGN_IDENTITY   the certificate, e.g. "Developer ID Application: Name (TEAMID)"   (required)
#                       list yours with:  security find-identity -v -p codesigning
#   LPX_NOTARY_PROFILE  keychain profile made once with `xcrun notarytool store-credentials`   (required with --notarize)
#
# --dry-run prints every command and runs none of them.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
APP="$HERE/../build/LPX Explorer.app"; notarize=0; dry=0
for a in "$@"; do
  case "$a" in
    --notarize) notarize=1 ;;
    --dry-run) dry=1 ;;
    -*) echo "unknown option $a" >&2; exit 2 ;;
    *) APP="$a" ;;
  esac
done
[ -n "${LPX_SIGN_IDENTITY:-}" ] || { echo "LPX_SIGN_IDENTITY is not set: export it as your 'Developer ID Application: …' certificate name (see docs/SIGNING.md)." >&2; exit 2; }
if [ "$notarize" = 1 ] && [ -z "${LPX_NOTARY_PROFILE:-}" ]; then
  echo "LPX_NOTARY_PROFILE is not set: notarizing needs a keychain profile from 'xcrun notarytool store-credentials' (see docs/SIGNING.md)." >&2; exit 2
fi
[ "$dry" = 1 ] || [ -e "$APP" ] || { echo "nothing to sign at $APP — build it first (scripts/make-app.sh, scripts/make-dmg.sh)" >&2; exit 1; }

run() { echo "+ $*"; if [ "$dry" = 0 ]; then "$@"; fi; }

case "$APP" in
  *.dmg)
    # A disk image: signed with a secure timestamp (no hardened runtime — that is for executables), submitted as it is.
    run codesign --force --timestamp --sign "$LPX_SIGN_IDENTITY" "$APP"
    run codesign --verify --strict --verbose=2 "$APP"
    if [ "$notarize" = 1 ]; then
      run xcrun notarytool submit "$APP" --keychain-profile "$LPX_NOTARY_PROFILE" --wait
      run xcrun stapler staple "$APP"
      run xcrun stapler validate "$APP"
      run spctl --assess --type open --context context:primary-signature --verbose=4 "$APP"
    fi
    echo "done: $APP is signed$( [ "$notarize" = 1 ] && echo ' and notarized')$( [ "$dry" = 1 ] && echo ' (dry run: nothing was executed)')"
    exit 0 ;;
esac

# 1. Sign with the hardened runtime and a secure timestamp (both are required for notarization).
run codesign --force --options runtime --timestamp --entitlements "$HERE/entitlements.plist" --sign "$LPX_SIGN_IDENTITY" "$APP"
run codesign --verify --strict --verbose=2 "$APP"

if [ "$notarize" = 1 ]; then
  ZIP="${TMPDIR:-/tmp}/lpx-notarize-$$.zip"
  # 2. Upload to Apple's notary service and wait for the verdict (needs network and the keychain profile).
  run ditto -c -k --keepParent --norsrc --noextattr --noqtn "$APP" "$ZIP"
  run xcrun notarytool submit "$ZIP" --keychain-profile "$LPX_NOTARY_PROFILE" --wait
  run rm -f "$ZIP"
  # 3. Attach the ticket so the app also opens offline, then check what Gatekeeper will say.
  run xcrun stapler staple "$APP"
  run xcrun stapler validate "$APP"
  run spctl --assess --type execute --verbose=4 "$APP"
fi
echo "done: $APP is signed$( [ "$notarize" = 1 ] && echo ' and notarized')$( [ "$dry" = 1 ] && echo ' (dry run: nothing was executed)')"
