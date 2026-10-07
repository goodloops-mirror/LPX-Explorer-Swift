import XCTest
@testable import LpxCore

final class GoldenAUTests: XCTestCase {
    static func key(_ a: [String: Any]) -> String {
        "\(a["type_code"]!)/\(a["subtype"]!)/\(a["manufacturer"]!)@\(a["offset"]!)#\(a["display_name"] as? String ?? "")"
    }

    static func key(_ a: AURef) -> String { "\(a.fingerprint)@\(a.offset)#\(a.displayName ?? "")" }

    /// Independent re-statement of the text-blob rule (kept separate from the implementation).
    static func hasTextAroundStandardDescriptor(_ raw: [UInt8], at off: Int) -> Bool {
        func text(_ r: Range<Int>) -> Bool { !r.isEmpty && r.allSatisfy { (0x20...0x7e).contains(raw[$0]) || [0x09, 0x0a, 0x0d].contains(raw[$0]) } }
        return text(max(0, off - 12) ..< (off - 4)) && text((off + 8) ..< min(raw.count, off + 16))
    }

    /// Swift must reproduce the legacy Rust parser's AUs on every real project, EXCEPT standard-triple
    /// hits that sit inside printable text blobs (base64 noise). Each removed hit is checked against
    /// the raw bytes independently, so the filter can't silently eat real descriptors.
    func testFindAUsMatchesRustOracleExceptTextBlobNoise() throws {
        var removedTotal = 0
        for c in try Golden.cases() {
            let rust = (c.json["aus"] as! [[String: Any]])
            let swift = AUFinder.findAUs(c.projectData).map(Self.key)
            let kept = rust.filter { swift.contains(Self.key($0)) }
            let removed = rust.filter { !swift.contains(Self.key($0)) }
            removedTotal += removed.count

            XCTAssertEqual(swift, kept.map(Self.key), "\(c.name): Swift found something Rust did not, or reordered")
            for r in removed {
                XCTAssertNil(r["display_name"] as? String, "\(c.name): a named (stock/Drummer) plug-in was dropped")
                XCTAssertTrue(Self.hasTextAroundStandardDescriptor(c.projectData, at: r["offset"] as! Int),
                              "\(c.name): dropped a hit that is not text-surrounded: \(Self.key(r))")
            }
        }
        XCTAssertGreaterThan(removedTotal, 0, "expected the example projects to contain text-blob noise")
    }

    /// Ground truth from this Mac: a plug-in that `auval -l` lists as installed is real, so the
    /// noise filter must never remove it. (Skipped when auval isn't available.)
    func testNoInstalledPluginIsFilteredOut() throws {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/auval")
        proc.arguments = ["-l"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        do { try proc.run() } catch { throw XCTSkip("auval unavailable") }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        let installed = Set(String(decoding: data, as: UTF8.self).split(whereSeparator: \.isNewline).compactMap { AuvalParser.parseLine(String($0))?.fingerprint })
        try XCTSkipIf(installed.isEmpty, "no installed AUs reported")

        var checked = 0
        for c in try Golden.cases() {
            let swift = Set(AUFinder.findAUs(c.projectData).map(Self.key))
            for r in (c.json["aus"] as! [[String: Any]]) where installed.contains("\(r["type_code"]!)/\(r["subtype"]!)/\(r["manufacturer"]!)") {
                checked += 1
                XCTAssertTrue(swift.contains(Self.key(r)), "\(c.name): installed plug-in removed: \(Self.key(r))")
            }
        }
        XCTAssertGreaterThan(checked, 100)
    }
}
