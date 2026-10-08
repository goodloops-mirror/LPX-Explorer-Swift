import XCTest

/// The quick guide ships with the app: a PDF in docs/ (made from docs/manual.html by `swift scripts/make-manual.swift`),
/// copied into the app bundle, and opened from the Help menu.
final class ManualTests: XCTestCase {
    private var root: URL { URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent() }

    func testTheManualPDFExists() throws {
        let data = try Data(contentsOf: root.appendingPathComponent("docs/LPX Explorer Manual.pdf"))
        XCTAssertEqual(String(decoding: data.prefix(5), as: UTF8.self), "%PDF-")
        XCTAssertGreaterThan(data.count, 10_000)
    }

    func testTheAppBundleGetsTheManual() throws {
        let script = try String(contentsOf: root.appendingPathComponent("scripts/make-app.sh"), encoding: .utf8)
        XCTAssertTrue(script.contains("docs/LPX Explorer Manual.pdf"))
        XCTAssertTrue(script.contains("Resources/Manual.pdf"))
    }

    func testTheHelpMenuOpensIt() throws {
        let app = try String(contentsOf: root.appendingPathComponent("Sources/LpxExplorer/LpxExplorerApp.swift"), encoding: .utf8)
        XCTAssertTrue(app.contains("CommandGroup(replacing: .help)"))
        XCTAssertTrue(app.contains("Manual.open()"))
    }

    func testTheManualMentionsTheMainFeatures() throws {
        let html = try String(contentsOf: root.appendingPathComponent("docs/manual.html"), encoding: .utf8)
        for topic in ["Getting started", "Searching", "Bounces", "Plug-ins", "read-only"] { XCTAssertTrue(html.contains(topic), topic) }
    }
}
