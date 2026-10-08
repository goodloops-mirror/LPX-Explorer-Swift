# lpx-explorer (SwiftUI)

Native macOS app (SwiftUI, macOS 14+) — a **read-only** inspector for Logic Pro `.logicx` bundles. It surfaces plug-ins, tracks and metadata from the undocumented binary `ProjectData` file without launching Logic.

This is a rewrite of the original Tauri/React/Rust app, which is kept untouched in `legacy-tauri/` as the reference (parser source of truth: `legacy-tauri/src-tauri/crates/lpx-parser/`, format notes: `legacy-tauri/docs/logicx-format.md`).

## Hard rules

- **Never push or open PRs — the owner pushes manually** to their own Forgejo (`origin`). The old `DISABLED_NO_PUSH` guard was removed on request, so nothing technical stops a push: don't. Commit locally only when asked.
- **Read-only contract.** Never write inside a `.logicx` bundle. `ProjectParserTests.testParseDoesNotMutateTheBundle` (SHA-256 + mtime) gates this. The app only writes to `~/Library/Application Support/LpxExplorer/`.
- **macOS only.** No cross-platform conditionals.
- **TDD, vertical slices.** One failing test → minimal code → repeat. Verify RED fails on missing *behaviour* (a stub returning empty), not on a compile error. Port the Rust tests in `legacy-tauri` alongside each Rust function.
- No npm / node on this machine. Don't add JS tooling.

## Releases

Versions are git tags `vX.Y.Z` (semver; legacy Tauri tags `v0.0.x` are ignored); the app starts at v0.1.0. `CHANGELOG.md` keeps hand-written notes under *Unreleased*. `scripts/release.sh <major|minor|patch|X.Y.Z> [--dry-run]` runs the tests, writes the new CHANGELOG section (notes + commit subjects since the last tag, grouped by `feat:`/`fix:`/other), commits it and tags it — it never pushes. `scripts/version.sh` reads the version from the tags (used by `make-app.sh`); `scripts/test-release.sh` tests the scripts in a temp repo. Only cut a release when asked.

## Layout

```
Package.swift
Sources/LpxCore/       parser + scanner (no UI, Foundation only)
Sources/LpxExplorer/   SwiftUI app
Sources/lpx-scan/      CLI: time/validate the scanner on a real folder (read-only)
Tests/LpxCoreTests/    XCTest suite
scripts/make-app.sh    builds "build/LPX Explorer.app" (ad-hoc signed)
legacy-tauri/          the original app, reference only
```

## Commands

```bash
swift test                              # all tests
swift run LpxExplorer                   # run the app unbundled
./scripts/make-app.sh                   # build a double-clickable .app
swift build -c release --product lpx-scan && .build/release/lpx-scan <folder> [workers]
```

## Test material & oracle

- **Only `example_projects/` may be read as real project data** (git-ignored, ~1.2 GB, large real projects). Never read or scan any other `.logicx` on the machine, and never commit `example_projects/` or `Tests/Golden/`.
- `scripts/make-golden.sh` runs the legacy Rust parser (`scripts/oracle/`, needs cargo) over `example_projects/` and writes `Tests/Golden/*.json`. `GoldenAUTests` / `GoldenTrackTests` require the Swift parser to reproduce those results exactly; they skip if either folder is missing. When changing a scanner, keep them green — they are the real regression net.
- **Known, intentional differences from the Rust oracle:** (1) `AUFinder` drops standard-triple hits inside printable text blobs (base64 noise) — the golden test checks each removal independently and that no installed plug-in is lost; (2) verdict counts unique plug-ins; (3) `aumf` is an audio effect in categories/grouping; (4) CAF is previewable. Update the golden tests, not the oracle, when adding such a deliberate difference.
- **Track list** (`ArrangementList` → `ArrangementTracks`) is verified against Logic's own display (the owner's screenshots of `example_projects`), not the Rust oracle (which has no such feature; `TrackPipeline.channelStrips` is the Rust-equivalent view the golden tests compare). Record layout: TASKS.md ("SOLVED … the arrangement track list").
- Debug-build golden tests take ~25 s; use `swift test --filter <TestClass>` while iterating.
- Profile stages with `swift build -c release --product lpx-scan && .build/release/lpx-scan example_projects --profile`.

## Local-only

The app makes **no network requests**: no updater, no analytics, no web search. `NoNetworkTests` scans `Sources/` for network/updater APIs and URLs, rejects `NSWorkspace.open` on anything but local files, and requires an empty dependency list. Don't add `URLSession`, WebKit, Sparkle, or any package. (Project files are only ever *revealed* in Finder, never opened.)

## Scan & storage architecture

`LogicxDiscovery` walks folders (bundles are leaves) → `LibraryScanner.scan` parses with a bounded worker pool (default 70% of logical cores). Whether a project changed is decided from a **stamp** (ProjectData mtime+size) kept in SQLite, so unchanged projects are never read: `LibraryScanner.changedBundles` stats them in parallel and only the new/modified ones are parsed.

Storage is `SummaryDatabase` (SQLite via the system `sqlite3`, `~/Library/Application Support/LpxExplorer/library.sqlite`, WAL):
- `entries` — a small `ProjectListEntry` per project (metadata, unique plug-ins with counts, track count, folded search text). Loaded in the background at launch (~0.3 s for 3,000 projects) and held in memory for the list, search, filters, verdicts and the plug-in view.
- `tracks` — one searchable row per arrangement track (folded name/object/channel/stock-plug-in text + plug-in fingerprints), rewritten with each project; powers the library-wide track search (`SummaryDatabase.searchTracks`, `lpx-scan --db <sqlite> --search <text>`). It is derived from `details`: bump `tracksVersion` when its columns/content change and it is rebuilt without re-parsing (`rebuildTracksIfNeeded`). `schemaVersion` / `parserVersion` bumps wipe everything.
- `failures` — projects that failed to parse, with the ProjectData stamp they failed at (retried only when it changes).
- `details` — the full `ProjectSummary` (tracks, alternatives, …), loaded only when a project is selected (~2 ms).
- Writes are incremental: only projects parsed in the last batch are upserted. Bump `SummaryDatabase.parserVersion` whenever parser output changes (rows are then dropped and re-derived).
- Always bind SQLite text/blobs with `SQLITE_TRANSIENT` (Swift's temporary buffers don't outlive the call).

UI: `OutcomeCollector` batches scan results → `LibraryModel` applies them every ~150 ms. The natural name sort is cached per folder (don't sort in view bodies; it cost ~0.5 s per refresh at 3,000 projects).

## When stuck

Don't re-derive the format. Read the Rust parser in `legacy-tauri/src-tauri/crates/lpx-parser/src/` and port its offsets and test fixtures.
