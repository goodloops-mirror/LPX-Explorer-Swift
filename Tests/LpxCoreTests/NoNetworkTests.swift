import XCTest

/// The app is local-only: no updater, no analytics, no web requests. This guards the source tree
/// (and the package manifest) against anything that could talk to the network.
final class NoNetworkTests: XCTestCase {
    private var root: URL { URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent() }

    private func swiftSources() throws -> [(path: String, text: String)] {
        let sources = root.appendingPathComponent("Sources")
        let e = try XCTUnwrap(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))
        return try e.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }.map { ($0.path, try String(contentsOf: $0, encoding: .utf8)) }
    }

    func testSourcesContainNoNetworkAPIsOrUpdaters() throws {
        let banned = [
            "URLSession", "URLRequest", "NSURLConnection", "NWConnection", "NWPathMonitor", "NWBrowser", "CFNetwork",
            "CFSocket", "CFStream", "WKWebView", "WebKit", "SafariServices", "Sparkle", "SUUpdater", "SPUUpdater",
            "http://", "https://", "ftp://", "ws://", "wss://", "URLComponents", "mailto:",
        ]
        let files = try swiftSources()
        XCTAssertGreaterThan(files.count, 5, "found the source tree")
        for (path, text) in files {
            for token in banned where text.contains(token) {
                XCTFail("\(path) mentions \(token): the app must stay local-only")
            }
        }
    }

    func testOnlyFileURLsAreEverOpenedWithTheWorkspace() throws {
        for (path, text) in try swiftSources() where text.contains("NSWorkspace.shared.open(") {
            // opening is allowed only for local paths (e.g. the saved window screenshot)
            for line in text.split(separator: "\n") where line.contains("NSWorkspace.shared.open(") {
                XCTAssertTrue(line.contains("fileURLWithPath"), "\(path): NSWorkspace.open must target a local file: \(line)")
            }
        }
    }

    func testPackageHasNoDependencies() throws {
        let manifest = try String(contentsOf: root.appendingPathComponent("Package.swift"), encoding: .utf8)
        XCTAssertFalse(manifest.contains(".package("), "no third-party packages (no updaters, no networking libraries)")
    }

    func testAppBundleTemplateHasNoUpdateOrNetworkKeys() throws {
        let script = try String(contentsOf: root.appendingPathComponent("scripts/make-app.sh"), encoding: .utf8)
        for key in ["SUFeedURL", "SUPublicEDKey", "NSAppTransportSecurity", "NSAllowsArbitraryLoads"] {
            XCTAssertFalse(script.contains(key), key)
        }
    }
}
