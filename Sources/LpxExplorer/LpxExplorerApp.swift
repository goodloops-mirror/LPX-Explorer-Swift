import AppKit
import SwiftUI

@main
struct LpxExplorerApp: App {
    @State private var registry: AuRegistry
    @State private var model: LibraryModel
    @State private var player = AudioPlayerModel()
    @State private var spaceBar = SpaceBarPlayback()
    /// Shared with the project detail's toolbar toggle; four panes need a wider minimum window than three.
    @AppStorage("showTracksPane") private var showTracksPane = true
    @Environment(\.openWindow) private var openWindow

    init() {
        let registry = AuRegistry()
        _registry = State(initialValue: registry)
        _model = State(initialValue: LibraryModel(registry: registry))
        // Lets `swift run` (no .app bundle) show a window and take focus.
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    var body: some Scene {
        WindowGroup("LPX Explorer") {
            ContentView()
                .environment(model)
                .environment(registry)
                .environment(player)
                .frame(minWidth: showTracksPane ? 1100 : 900, minHeight: 560)
                .task {
                    if registry.needsScan { registry.refresh() }
                    model.start()
                    spaceBar.install(player: player)
                }
        }
        .defaultSize(width: 1500, height: 860)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About LPX Explorer") { openWindow(id: "about") }
            }
            CommandGroup(after: .toolbar) {
                Button("Reset Column Widths") { model.resetColumnWidths() }
            }
            CommandGroup(replacing: .newItem) {
                Button("Add Folder…") { model.chooseFolder() }.keyboardShortcut("o")
                Button("Rescan Library") { model.rescanAll() }.keyboardShortcut("r")
            }
        }
        Window("About LPX Explorer", id: "about") {
            AboutView()
        }
        .defaultSize(width: 480, height: 640)
        .windowResizability(.contentMinSize)
    }
}
