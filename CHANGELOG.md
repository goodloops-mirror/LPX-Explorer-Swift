# Changelog

All notable changes to LPX Explorer. Versions are git tags (`vX.Y.Z`, [semantic versioning](https://semver.org));
`scripts/release.sh` turns the *Unreleased* notes plus the commit subjects since the last release into a new section.
Earlier versions (v0.0.x) belong to the retired Tauri app in `legacy-tauri/`.

## [Unreleased]

### Added
- About window (resizable, shows the exact build): Good Loops branding and logo, acknowledgement of the original author (Rhyd Lewis), GPL-3.0-or-later notice, and placeholders for the source repository and Buy Me a Coffee links (shown as "coming soon" until configured in `AboutInfo`).
- `LICENSE` (GPL-3.0-or-later) and a licence/credits section in the README.

## [0.4.0] - 2026-10-08

### Changed
- Add the app icon

## [0.3.0] - 2026-10-08

### Changed
- Search results are a list of matching projects, each followed by the tracks/objects inside it that matched. The toolbar search box matches everything (project, track, object and channel names, plug-ins); the three fields above the list match only their own field (project names / track and object names / plug-ins), and everything typed must match. The fields are always visible above the project list; typing in any of them switches to the library-wide results.

### Fixed
- Search finds projects again by track names, object names and plug-ins, not just project names: projects that match as a whole are listed even without per-track rows (the field filters apply to them too).
- Projects whose arrangement list couldn't be read (channel strips without track numbers) are now searchable per track; the results footer says when per-track results don't cover every project.

### Changed
- Launch only stats the projects' ProjectData and parses what is new or modified; with nothing changed there is no progress bar and no parsing. The banner now reads "Updating N new or changed projects".
- Projects that failed to parse are remembered (with their file stamp) and retried only when the file changes.
- Changing the track-search table layout rebuilds it from the stored summaries instead of re-parsing the whole library.
- The app says so when it cannot open its library database (it would otherwise re-read everything at every launch).

### Fixed
- search projects by track names and plug-ins again

### Changed
- Make the whole track result row clickable
- Make search results project-centric with per-field filters
- Only parse new or changed projects at launch
- Package releases as a zip; version follows the checked-out commit

## [0.2.0] - 2026-10-08

### Changed
- Show the XCTest summary in release.sh

## [0.1.0] - 2026-10-08

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

