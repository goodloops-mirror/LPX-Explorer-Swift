import AppKit
import SwiftUI

@main
struct LpxExplorerApp: App {
    @State private var registry: AuRegistry
    @State private var model: LibraryModel

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
                .frame(minWidth: 900, minHeight: 560)
                .task {
                    if registry.needsScan { registry.refresh() }
                    model.start()
                }
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Add Folder…") { model.chooseFolder() }.keyboardShortcut("o")
                Button("Rescan Library") { model.rescanAll() }.keyboardShortcut("r")
            }
        }
    }
}
