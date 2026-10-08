import AppKit

/// The quick guide (a PDF in the app's Resources) opened in the user's PDF viewer from the Help menu. A local file only.
enum Manual {
    static func open() {
        // In the built app the PDF is in Resources; with `swift run` from the repository it is in docs/.
        let candidates = [Bundle.main.url(forResource: "Manual", withExtension: "pdf")?.path,
                          FileManager.default.currentDirectoryPath + "/docs/LPX Explorer Manual.pdf"].compactMap { $0 }
        guard let path = candidates.first(where: { FileManager.default.fileExists(atPath: $0) }) else {
            let alert = NSAlert()
            alert.messageText = "The manual isn't available in this build"
            alert.informativeText = "It is included in the app built with scripts/make-app.sh (docs/LPX Explorer Manual.pdf)."
            alert.runModal()
            return
        }
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }
}
