# LPX Explorer

Native SwiftUI inspector for Logic Pro `.logicx` projects. Read-only. Shows tempo, key, tracks, size and the plug-ins used (with real names via `auval -l`), and searches across project names and plug-in names.

```bash
swift test
./scripts/make-app.sh && open "build/LPX Explorer.app"
```

Requires macOS 14+ and Xcode 16 / Swift 6 toolchain. See `CLAUDE.md` for architecture and `TASKS.md` for what is ported and what is still open. The original Tauri app lives in `legacy-tauri/`.
