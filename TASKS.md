# Tasks

LPX Explorer is its own app now; the Tauri code in `legacy-tauri/` is only a format reference and a regression oracle (`scripts/make-golden.sh`). Releases are versioned with git tags and recorded in `CHANGELOG.md` (`scripts/release.sh`).

`bd` is not installed here; track work in this file until it is.

## Done
- [x] Package skeleton, `LpxCore` / `LpxExplorer` / `lpx-scan`
- [x] `AUFinder.findAUs` — standard 4CC triples (aumu/aufx/aumf/aumi) with printable-ASCII noise filter
- [x] `MetadataParser` (MetaData.plist)
- [x] `LogicxDiscovery`, `ProjectParser` (+ read-only SHA-256 invariant), bundle stats
- [x] `LibraryScanner` — bounded parallel pool (70% cores), cache validation, failure isolation
- [x] `ParseCacheStore`, `AuvalParser` (+ `AuRegistry` running `auval -l`)
- [x] `SearchMatcher` — project name + plug-in names (+ track names once parsed)
- [x] App: folder sidebar, project list, inspector (metadata, plug-ins by kind), scan banner, drag-and-drop, Reveal / Open in Logic
- [x] Measured: 1500 synthetic 600 KB bundles scan in ~1.4 s (1 worker) → ~0.24 s (8 workers)

- [x] `AppleStock`, `AppleDrummer`, `Regions`, `TrackRegistry`, `TrackFinder`, `TrackPipeline` — **golden tests reproduce the legacy Rust parser's output exactly** (regression net) on all 24 `example_projects` (12,677 channel strips, 2,152 AU refs, every registry/region record)
- [x] Search matches track names (inspector Tracks section)
- [x] Scan optimised with memchr jumps: ~6.4 → ~1.1 ms/MB of ProjectData; 24 projects / 944 MB: 1.14 s on 1 worker, 0.13 s on 14
- [x] Summary stores only active user-visible tracks (+ routing strips with inserts): cache 66 → 26 KB/project

- [x] Alternatives: manifest parser, per-variant parse (`ProjectParser.parse(bundle:variant:)`), "N alts" badge, variant picker in the inspector (parsed on demand), alternative names searchable
- [x] Inspector: window screenshot, "Saved with Logic Pro …", missing-`ProjectInformation.plist` warning
- [x] Audio inventory (`AudioInventory`): bounces / recordings / freeze files under root, `Media/` and every alternative; durations via AVFoundation; smart "hero" pick; in-app player (play/pause/scrub) and Reveal in Finder
  - NB: `example_projects/` contains **no audio files and only variant 000**, so these are covered by synthetic-bundle unit tests (incl. real generated WAVs) — not by golden data. Worth verifying by hand on a project that has bounces and multiple alternatives.
  - CAF counts as previewable (AVFoundation plays it).

- [x] Compatibility verdict (`CompatibilityVerdict`): clean / N missing / will-not-open / unknown, shown as a band atop the inspector with a "Show what's missing" list (names + which tracks use each); warning marker on project rows
  - Counts **unique** plug-ins, not instances.
- [x] Similarity filters (`SimilarityAxis`, `LibraryFilter`): click Key / Tempo / "Find similar" in the inspector → filter chip over the project list; "Missing plug-ins only" toggle
- [x] ~~Investigate possible false "missing" plug-ins~~ **Fixed.** Cause: type tags occurring by chance inside base64/plist text blobs in ProjectData. `AUFinder` now rejects a candidate when the 8 bytes before the manufacturer and the 8 bytes after the subtype are all text. Evidence on `example_projects`: 114/114 false hits were text-surrounded, 0/1,439 real (installed) ones were; all 24 projects now say "Opens cleanly". Golden tests encode this (Swift = Rust minus text-blob hits; no installed plug-in is ever removed). Original note:: on `example_projects`, 49 unique plug-ins flagged missing on this Mac, 22 of them in a single project, several with noise-like 4CCs (e.g. `aumu/+WZw/Rik/`). The Rust parser reports the same fingerprints (golden-verified), so this is inherited behaviour. Needs ground truth: which of these projects really complain about missing plug-ins in Logic?
- [ ] Key pivot is useless when the key was never set (Logic stores C major by default; all 24 examples say C major). Consider hiding the key pivot / treating default key as unknown.

- [x] Plug-in rail: sidebar "Plug-ins" view — library-wide usage (projects / instances), install status, category facets + "M of N categorised", status filter, search by name or fingerprint, detail pane listing projects (click to jump), Search the Web / Copy Name
  - `aumf` ("music effect", e.g. FabFilter Pro-Q 3) is now an **audio** effect in categories and the inspector grouping; `Track.midiFx` still holds aumf+aumi (kept so the golden tests match the oracle) — group by `typeCode` when presenting.
  - 20 of 63 plug-ins in the examples are "Uncategorised" (third-party names; the table only knows Apple stock plug-ins). **Decision: no keyword/heuristic categorisation** — the owner knows their plug-ins.
- [ ] Per-project rail scope (only the library-wide view exists)

- [x] **SQLite cache** replaces the JSON file (`SummaryDatabase`): list entries in the background at launch (~0.3 s / 3,000 projects vs 2.2 s blocking), change detection from stamps only (4 ms), incremental saves (50 projects: 68 ms vs ~3 s), full summary loaded on selection (~2 ms). Also fixed: per-refresh list sort (512 ms → cached), plug-in rollup O(n²) (500 → 33 ms), search (159 → 4 ms per keystroke at 3,000 projects).
- [x] **Local-only**: no Sparkle/network anywhere in the Swift app (`NoNetworkTests`); "Search the Web" removed; legacy Sparkle framework, signing tools, appcast/release scripts and workflow deleted (`legacy-tauri/README-LEGACY.md`)
- [x] Reveal in Finder replaces "Open in Logic" in the inspector toolbar; right-click a project (or use the toolbar) → Reveal in Finder / Copy Path

- [ ] **Arrangement track numbers (Logic's "1, 2, 3 … 43" order) — NOT recoverable yet.** Investigated 2026-10-07 using the ground truth in each project's `WindowImage.jpg` (e.g. *To The Mountains v01*: CUE=1, DX=2, FX=3, MX=4, SYNTHS=13, AQU…theremin=14, GTR=17, AQU…lyre=18, SYNTHS MALLETS=42, Vibra=43; numbers count hidden tracks inside collapsed folders). Ruled out:
  - byte order of channel strips (Audio first, then Inst…) and of registry records (storage order: audio/instrument interleaved, strip ids jump);
  - `DisplayState.plist` / `DisplayStateArchive` (window/mixer UI state only);
  - `track_id` (object IDs; stride 64 per created track, not arrangement order), the registry trailer fields (strip id, then a small index that doesn't match track numbers), channel-strip descriptor bytes (flags), and `karT` records (MIDI environment objects such as "Logic Pro Virtual In").
  - No sequence of track IDs appears adjacent in the file, so the order is not a plain ID list.
  Findings worth keeping: the registry whitelist misses many record types (the 2-byte "signature" is really an object-class number: 0x1199 `Vibra`/`Click`, 0x119c Aux, 0x11eb/0x10c7/0x11f4 audio variants…); folders like CUE/SYNTHS/GTR are not in the parsed registry at all. A real answer needs deeper reverse-engineering of the arrangement object graph (use the 24 screenshots as test oracle).
  Fallbacks that *are* possible: sort tracks by name/kind; show the screenshot (already shown).
  - **Round 2 (owner clarified: hidden tracks are numbered like all others and are *not* inside folders).** Still not found. Checked on *To The Mountains v01* (10.7 MB): (a) no 1/2/4-byte field within ±160 bytes of any registry-shaped record equals, is one off, or increases in the order of the real numbers DX=2, FX=3, MX=4, theremin=14, lyre=18, Vibra=43; (b) the registry-shaped records are NOT in track-number order in the file (FX, MX, then DX, then Vibra, theremin, lyre); (c) `qSxT` (45 records at the very end of the file, ~140 B apart) are marker/text events (names like CUE, PIANO, SYNTHS, STR, CHOIR); `qeSM`/`qSvE` pairs are region/sequence records (names repeat ~8× each); (d) other tags with counts near 43 (`QAkg`, `XAPq`, `HnCA`) are base64 text noise; (e) the 64 registry-shaped records in the 8.7–9.0 MB area include system objects (Master, Click, Stereo Out), 7 Aux, many audio/instrument tracks — signature = object class, not a constant.
  - **Round 3 (owner provided full ground truth, 2026-10-07):** *To The Mountains v01* was re-saved with one region named `TRACK n` on each of its 46 tracks (n = Logic's sequential track number; hidden tracks count; folders are ordinary "banner" tracks and contain nothing; track 46 is hidden). Full list in the owner's screenshot: 1 CUE, 2 DX, 3 FX, 4 MX, 5 EP 11…, 6–9 Audio 6–9, 10 PIANO, 11 accordian, 12 Tranquil…, 13 SYNTHS, 14 theremin, 15 HARP, 16 Harp 1, 17 GTR, 18 lyre, 19 WOODS, 20 flute, 21 clarinet, 22 bass clarinet, 23 ocarina, 24 BRASS, 25 cornet, 26 SOLO STR, 27/28 Strings Tk#01/#02, 29 STR, 30 ALB5…, 31 BH Harmonics, 32 Strings Tk#01, 33 Audio 33, 34/35 Tk#04/#05, 36 Audio 34, 37 CHOIR, 38 NOVELLA…, 39–41 Choir Tk#02/05/08, 42 SYNTH…LLETS, 43 Vibra, 44 Vibra, 45 MALLETS, 46 AQU…marimba (hidden). **Names are user-set labels, never identifiers.**
  - Findings: the 46 `TRACK n` regions are standalone `karT`/`qSvE`/`qeSM` triples (~429 B each) stored in strictly increasing n order (n=5…46 back to back; 1–3 and 4 elsewhere) — region order = track order, OR simply the order the owner created them (unknown). A region's header holds NO track number (no field == n, n±1 at any consistent offset), NO owner ID shared with the registry `track_id`/strip records (searched all numeric fields), and its `qSvE.ref` values (e.g. 3138, 2770…) occur only in their own record. Regions form a linked chain (region n's trailing u16 == region n+1's `qSvE.ref`).
  - Registry-shaped records (the named tracks) are in file order 3,4,30,6,7,8,9,38,2,… (NOT track order, also after re-save); `qSxT` per-track text/notes objects are in yet another order; `DisplayState*` has no arrangement list.
  - Not tried yet: a general chunk-graph parser (frame = tag + version + 0x17 + id…), and the **minimal-edit diff experiment** — a baseline copy of the numbered project's ProjectData is saved in the session scratchpad (`baseline/ToTheMountains-v01-numbered-ProjectData.bin`, sha256 prefix in chat); after the owner drags ONE track to a new position and saves, diffing the two files should isolate the bytes that encode order.
  - **Round 4 — FOUND where track numbers live (2026-10-07).** The owner moved track 1 (CUE) to position 4 and re-saved; old/new `ProjectData` are the same size, and diffing them showed the number is stored explicitly:
    - Record shape (all in the serialized object stream): `…[X u32][n u16] 00 89 00 00 00 00 ff ff ff 3f [ID u32]…` — `X` = the track's key (an object ID), `n` = a position number. Appears in several lists; the 80-byte "table" entries (prefix has `87 00 00` at pre[5:8]) are an index of ANOTHER list (e.g. DX=9) or, in the numbered project, a first-region table (n=1..46). **Region/event entries** (every region/event on a track carries its track's current position) are the reliable source: all of a track's non-table entries share one `n`.
    - **Link to the named track:** the track's registry-shaped name record (4 zeros · class · …· len · name) carries its key `X` as a u32 at **−170** and again at **−128** bytes before the record start. (Folder/banner tracks share key 0x10 — their names are not linked yet.)
    - **Rule:** position(track) = the single `n` among non-table `[X][n]…89…` entries with that key. Verified: numbered project 31/31 named tracks before the move AND 31/31 after (DX/FX/MX 2,3,4 → 1,2,3); Alea v01's visible tracks 9/9 incl. tracks inside a summing stack (a "smallest n" shortcut fails there: 17 vs truth 20).
    - Across all 24 examples (859 audio/instrument registry tracks): 696 get one consistent position, **0 duplicate positions in any project**, 36 have conflicting values (unexplained), 127 have no region/event entries at all (empty tracks, position unknown — maybe recoverable from the table type).
    - `code_from_other_people/logicx-analyzer` (third-party RE notes) contains nothing on track order/numbers; it only lists the same fourCCs.
    - Not done: implementation in Swift, folder/banner track names↔positions, the 36 conflicts, the 127 empty tracks, hidden-flag.
  - **Needed to continue (ask owner):** the full numbered track list of one project with *all* tracks unhidden (name, type, number) as ground truth, plus answers on how Logic numbers/links tracks (see the questions in the chat on 2026-10-07).

- [x] **Track list = Logic's arrangement** (`ArrangementList`, `NameTexts`, `TrackObjects`, `ArrangementTracks`, `TrackPipeline.tracks`): one track per 93-byte `karT` record in track order, hidden tracks, folders/banners, tracks without regions and several tracks per object all included; each track has its own name (its `qSxT` text, else the object's name), position, object name, hidden flag (bit 0x04 at record+43), and the channel strip + plug-ins of its object. The inspector shows `#`, Channel, Name (+ hidden marker and "Object: …" when a track's name differs from its object). Projects without a recognisable list fall back to the old filtered channel strips. Verified against the owner's screenshots (numbered project incl. two tracks on one object, *Alea v01* hidden rows 5–15 and summing stack, *Please Follow me v01* shared objects/folders/Harp 1 = Inst 61) and structurally on all 26 example projects (positions 1…N, no gaps). The earlier region-entry "position" heuristic (`TrackPositions`) was removed.
  - Known gaps: kind of tracks whose object has no channel strip we can link (summing stacks, "No Output" object tracks) is `.unknown`; the record's other bytes (type 1/5/10, UUID, remaining flags) are undecoded; `Stereo Out` output record and the trailing sentinel are skipped by rule (type byte 3 / index 0x7fffffff).

- [x] **Library-wide track search**: one row per arrangement track in SQLite (`tracks`), results grouped by project with hidden tracks marked, click opens the project at the track; drill-down filters (project, track/object name, plug-in, kind, hidden); default columns 15 / 50 / 35 % with *Reset Column Widths*
- [x] **Release process**: git tags `vX.Y.Z`, `CHANGELOG.md`, `scripts/release.sh`; the app bundle takes its version from the latest tag

## Open
- [ ] Track hierarchy: `parentOffset`/`subNumber` are never set; folders/stacks render flat
- [ ] Golden tests take ~25 s (debug build); `swift test --filter` for quick runs
- [ ] Waveform drawing for the audio player (currently a scrubber only)
- [ ] Full-size window-image lightbox (currently opens in Preview on click)
- [ ] Visual QA of Alternatives / Audio sections with a project that actually has them
- [ ] Recents + menu, sort options
- [ ] Worker-count tuning: this Mac has 16 P + 4 E cores; 14 workers (70% of 20) measured *slower* than 8. Consider 70% of performance cores, or make it a setting.
- [ ] Discovery speed: walking a whole home folder took ~52 s; consider `fts`/`getattrlistbulk` and skipping `~/Library`, `.Trash`, node_modules-like dirs.
- [ ] Pause/resume (current UI only has Stop; rescan resumes via cache)
- [ ] Visual QA of the SwiftUI views (built and launch-tested, not yet eyeballed)
