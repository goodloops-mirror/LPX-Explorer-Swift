# LPX Explorer

Native SwiftUI inspector for Logic Pro `.logicx` projects. Read-only. Shows tempo, key, tracks, size and the plug-ins used (with real names via `auval -l`), and searches across project names and plug-in names.

```bash
swift test
./scripts/make-app.sh && open "build/LPX Explorer.app"
```

Requires macOS 14+ and Xcode 16 / Swift 6 toolchain. See `CLAUDE.md` for architecture and `TASKS.md` for what is ported and what is still open. The original Tauri app lives in `legacy-tauri/`.


## Licence and credits

LPX Explorer is free software, **GPL-3.0-or-later** (see [`LICENSE`](LICENSE)): you may use, change and share it; distributed derivatives must stay GPL and come with their source.

It is a native rewrite of the original **LPX Explorer by Rhyd Lewis** (GPL-3.0-or-later), whose reverse-engineering of the `.logicx` format (kept in [`legacy-tauri/`](legacy-tauri/), with its own `LICENSE`) this app builds on. Thank you.

Published by [Good Loops](https://www.good-loops.com).
