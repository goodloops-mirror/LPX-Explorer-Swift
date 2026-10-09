# Signing and notarizing LPX Explorer

A build that is only ad-hoc signed (what `scripts/make-app.sh` makes) is blocked by Gatekeeper on other Macs. A release that is
**signed with a Developer ID certificate and notarized by Apple** opens with a plain double-click. Everything below happens on
your Mac; the app itself still makes no network requests (notarizing talks to Apple only while you build a release).

## What you need

1. **A "Developer ID Application" certificate** in your login keychain (Apple Developer Program, paid). Check:

   ```bash
   security find-identity -v -p codesigning
   ```

   The line `"Developer ID Application: Your Name (TEAMID)"` is your identity. The name inside the quotes is what Gatekeeper shows
   as the publisher. (A personal membership shows your own name. To show "Good Loops" the membership has to be an *organization*
   one.)

2. **A notarization login, stored once.** Create an *app-specific password* at <https://appleid.apple.com> (Sign-In and
   Security ▸ App-Specific Passwords), then:

   ```bash
   xcrun notarytool store-credentials "lpx-notary" --apple-id "you@example.com" --team-id "TEAMID" --password "xxxx-xxxx-xxxx-xxxx"
   ```

   This keeps the login in your keychain under the name `lpx-notary`; no password lives in this repository or in a script.

## Releasing a signed app

Put these two lines in your shell profile (or export them before releasing):

```bash
export LPX_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
export LPX_NOTARY_PROFILE="lpx-notary"
```

Then the normal release does everything — build the app, sign it (hardened runtime, secure timestamp), notarize and staple it, put it in a disk image (`.dmg`, with an Applications shortcut), sign that, notarize and staple it too. The DMG in `dist/` is what you publish:

```bash
scripts/release.sh minor        # or: scripts/package.sh   for just the disk image
```

- With only `LPX_SIGN_IDENTITY` set the app and the image are signed but not notarized (fine for testing; Gatekeeper still objects elsewhere).
- Without either, the app is ad-hoc signed as before.
- `scripts/sign-app.sh --dry-run [--notarize]` shows exactly what would run without running anything; it accepts the `.app` or the `.dmg`. `scripts/make-dmg.sh` builds just the image.

## Checking the result

```bash
codesign --verify --strict --verbose=2 "build/LPX Explorer.app"
spctl --assess --type execute --verbose=4 "build/LPX Explorer.app"   # "accepted  source=Notarized Developer ID"
xcrun stapler validate "build/LPX Explorer.app"
spctl --assess --type open --context context:primary-signature --verbose=4 dist/LPX-Explorer-vX.Y.Z.dmg
xcrun stapler validate dist/LPX-Explorer-vX.Y.Z.dmg
```

The most honest test is the real one: download the dmg on another Mac (so it gets the quarantine flag) and open it.

## Bundle identifier

Builds use `local.lpx-explorer` unless `LPX_BUNDLE_ID` is set. For public releases use an identifier you own, e.g.
`export LPX_BUNDLE_ID="com.good-loops.lpx-explorer"`. Settings macOS keeps per bundle identifier (the list of library folders, the
tracks-pane toggle) start empty when the identifier changes once; the library cache itself is not affected.

## Notes

- The hardened runtime needs no special permissions here (`scripts/entitlements.plist` is empty on purpose): the app is not
  sandboxed, loads no third-party code and only reads what you point it at.
- The first time `codesign` uses the certificate, macOS may ask for permission to use its private key. Choose "Always Allow".
- Notarization usually takes 1–5 minutes; `--wait` blocks until Apple has answered. If it is rejected, the script stops and
  `xcrun notarytool log <submission-id> --keychain-profile lpx-notary` shows why.
