#!/bin/bash
# Build a double-clickable LPX Explorer.app (ad-hoc signed, local use only).
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# LPX_APP_SRC: build another checkout (package.sh uses it for old release tags) with these scripts.
cd "${LPX_APP_SRC:-$HERE/..}"
export LPX_VERSION_REPO="$PWD"
VERSION="$("$HERE/version.sh")"          # latest release tag, e.g. 0.1.0
BUILD="$("$HERE/version.sh" --build)"   # commit count
DESCRIBE="$("$HERE/version.sh" --describe)"  # e.g. 0.1.0-3-gabc123-dirty (what exactly is built)
swift build -c release --product LpxExplorer
APP="build/LPX Explorer.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/LpxExplorer "$APP/Contents/MacOS/LpxExplorer"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>LPX Explorer</string>
  <key>CFBundleDisplayName</key><string>LPX Explorer</string>
  <key>CFBundleIdentifier</key><string>local.lpx-explorer</string>
  <key>CFBundleExecutable</key><string>LpxExplorer</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$BUILD</string>
  <key>LpxBuildDescription</key><string>$DESCRIBE</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$APP" >/dev/null
echo "Built: $APP ($DESCRIBE)"
