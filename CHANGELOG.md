# Changelog

All notable changes to LPX Explorer. Versions are git tags (`vX.Y.Z`, [semantic versioning](https://semver.org));
`scripts/release.sh` turns the *Unreleased* notes plus the commit subjects since the last release into a new section.
Earlier versions (v0.0.x) belong to the retired Tauri app in `legacy-tauri/`.

## [Unreleased]

First release of the native SwiftUI app.

### Added
- Read-only inspector for Logic Pro `.logicx` projects: metadata, plug-ins by kind, window screenshot, alternatives, audio inventory with an in-app player.
- Arrangement track list in Logic's own order: track numbers, hidden tracks, per-track names, shared channel objects ("Object:"), folders.
- Library-wide track search with drill-down filters (project, track/object name, plug-in, kind, hidden); click a result to open the project at that track.
- Plug-ins view: library-wide usage, install status, categories.
- Compatibility verdict per project (missing plug-ins), similarity filters (key / tempo), "Missing plug-ins only".
- Parallel scanner (70% of cores) with a SQLite cache; unchanged projects are not re-read.
- Reveal in Finder and Copy Path; default column layout 15 / 50 / 35 % with *Reset Column Widths*.

### Notes
- Local only: no network requests, no updater. Never writes inside a project bundle.
