# legacy-tauri — reference only

The original Tauri/React/Rust app, kept so the Swift port can read the reverse-engineered parser
(`src-tauri/crates/lpx-parser`) and the original behaviour. **It is never built or run.**

The auto-update machinery (Sparkle framework + signing tools, appcast and release scripts, release
workflow and docs) has been deleted. Source files here still *mention* Sparkle, GoatCounter analytics
and web search (`lib.rs`, `Cargo.toml`, `Info.plist`, `src/lib/goatcounter.ts`, `search-engines.ts`, …);
that code is dead reference material. The Swift app (repo root) is local-only and makes no network
requests — `Tests/LpxCoreTests/NoNetworkTests.swift` enforces this.
