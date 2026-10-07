import CryptoKit
import XCTest
@testable import LpxCore

final class ProjectParserTests: XCTestCase {
    func testParsesFingerprintsMetadataAndStats() throws {
        let dir = try Fixture.tempDir()
        let bundle = try Fixture.logicx(in: dir, name: "song.logicx",
            plistBody: "<key>BeatsPerMinute</key><real>98.5</real><key>NumberOfTracks</key><integer>4</integer>")

        let s = try ProjectParser.parse(bundle: bundle)

        XCTAssertEqual(s.fingerprints.map(\.fingerprint), ["aumu/EZk2/Toon"])
        XCTAssertEqual(s.metadata.bpm, 98.5)
        XCTAssertEqual(s.metadata.trackCount, 4)
        XCTAssertGreaterThan(s.stats.sizeBytes, 0)
        XCTAssertEqual(s.projectDataSize, 20)
        XCTAssertEqual(s.path, bundle.path)
    }

    func testSummaryIncludesTracksWithAssignedPlugins() throws {
        func field(_ name: String) -> [UInt8] {
            var f = [0x20] + Array(name.utf8)
            return [0x00] + f + [UInt8](repeating: 0, count: 16 - f.count) + [0x29, 0x00, 0xF3, 0xC5, 0x01, 0, 0, 0] // byte 4 != 0 → active
        }
        let au = Array("PADDING_".utf8) + Array("nooT".utf8) + Array("umua".utf8) + Array("2kZE".utf8)
        let dir = try Fixture.tempDir()
        let bundle = try Fixture.logicx(in: dir, name: "tracks.logicx", projectData: field("Inst 1") + au)

        let s = try ProjectParser.parse(bundle: bundle)

        XCTAssertEqual(s.tracks.map(\.name), ["Inst 1"])
        XCTAssertEqual(s.tracks.first?.kind, .instrument)
        XCTAssertEqual(s.tracks.first?.instrument?.fingerprint, "aumu/EZk2/Toon")
    }

    /// Logic creates hundreds of default/unused channel strips and ~256 buses. The summary keeps
    /// only active user-visible tracks, plus routing strips that carry plug-ins.
    func testSummaryKeepsOnlyActiveUserVisibleTracksAndRoutingWithInserts() throws {
        func strip(_ name: String, head: UInt8, b2: UInt8 = 0, active: Bool) -> [UInt8] {
            let f = [0x20] + Array(name.utf8)
            let desc: [UInt8] = [head, 0x00, b2 | (active ? 0x04 : 0), 0xC5, 0, 0, 0, 0]
            return [0x00] + f + [UInt8](repeating: 0, count: 16 - f.count) + desc
        }
        func au(_ type: String, _ sub: String) -> [UInt8] {
            Array("PADDING_".utf8) + Array("nooT".utf8) + Array(type.reversed().map { String($0) }.joined().utf8) + Array(sub.reversed().map { String($0) }.joined().utf8)
        }
        let data = strip("Audio 1", head: 0xAB, active: true)
            + strip("Audio 2", head: 0xAB, active: false)
            + strip("Bus 1", head: 0xE9, active: true)
            + strip("Bus 2", head: 0xE9, active: true) + au("aufx", "Rvrb")
            + strip("Inst 1", head: 0x29, b2: 0xF3, active: true)
        let dir = try Fixture.tempDir()
        let bundle = try Fixture.logicx(in: dir, name: "phantoms.logicx", projectData: data)

        let s = try ProjectParser.parse(bundle: bundle)

        XCTAssertEqual(s.tracks.map(\.name), ["Audio 1", "Bus 2", "Inst 1"])
    }

    func testMissingProjectDataThrows() throws {
        let dir = try Fixture.tempDir()
        let bundle = dir.appendingPathComponent("empty.logicx")
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)

        XCTAssertThrowsError(try ProjectParser.parse(bundle: bundle)) {
            XCTAssertEqual($0 as? ParseError, .projectDataMissing(bundle.path))
        }
    }

    func testMissingMetadataPlistThrows() throws {
        let dir = try Fixture.tempDir()
        let bundle = try Fixture.logicx(in: dir, name: "nometa.logicx")
        try FileManager.default.removeItem(at: bundle.appendingPathComponent("Alternatives/000/MetaData.plist"))

        XCTAssertThrowsError(try ProjectParser.parse(bundle: bundle)) {
            XCTAssertEqual($0 as? ParseError, .metadataMissing(bundle.path))
        }
    }

    /// Read-only contract: parsing must not change any byte, mtime or file count.
    func testParseDoesNotMutateTheBundle() throws {
        let dir = try Fixture.tempDir()
        let bundle = try Fixture.logicx(in: dir, name: "sealed.logicx")
        let before = try snapshot(bundle)

        _ = try ProjectParser.parse(bundle: bundle)

        XCTAssertEqual(try snapshot(bundle), before)
    }

    private func snapshot(_ bundle: URL) throws -> [String: String] {
        var out: [String: String] = [:]
        let e = FileManager.default.enumerator(at: bundle, includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey])!
        for case let url as URL in e {
            let v = try url.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey])
            guard v.isRegularFile == true else { continue }
            let hash = SHA256.hash(data: try Data(contentsOf: url)).map { String(format: "%02x", $0) }.joined()
            out[url.path] = "\(hash)@\(v.contentModificationDate!.timeIntervalSince1970)"
        }
        return out
    }
}

final class ProjectParserVariantTests: XCTestCase {
    private func twoVariantBundle() throws -> URL {
        let dir = try Fixture.tempDir()
        let bundle = try Fixture.logicx(in: dir, name: "multi.logicx")
        let alt1 = bundle.appendingPathComponent("Alternatives/001")
        try FileManager.default.createDirectory(at: alt1, withIntermediateDirectories: true)
        try Data(Array("PADDING_".utf8) + Array("nooT".utf8) + Array("xfua".utf8) + Array("pmoC".utf8)).write(to: alt1.appendingPathComponent("ProjectData"))
        try Data(#"<?xml version="1.0"?><plist version="1.0"><dict><key>BeatsPerMinute</key><real>77</real></dict></plist>"#.utf8)
            .write(to: alt1.appendingPathComponent("MetaData.plist"))
        let res = bundle.appendingPathComponent("Resources")
        try FileManager.default.createDirectory(at: res, withIntermediateDirectories: true)
        try Data("""
        <?xml version="1.0"?><plist version="1.0"><dict>
        <key>LastSavedFrom</key><string>Logic Pro 12.2 (6644)</string>
        <key>VariantNames</key><dict><key>0</key><string>Main</string><key>1</key><string>Alt</string></dict>
        </dict></plist>
        """.utf8).write(to: res.appendingPathComponent("ProjectInformation.plist"))
        return bundle
    }

    func testParsesTheRequestedVariant() throws {
        let bundle = try twoVariantBundle()

        let v1 = try ProjectParser.parse(bundle: bundle, variant: 1)

        XCTAssertEqual(v1.fingerprints.map(\.fingerprint), ["aufx/Comp/Toon"])
        XCTAssertEqual(v1.metadata.bpm, 77)
        XCTAssertEqual(v1.variant, 1)
        XCTAssertEqual(try ProjectParser.parse(bundle: bundle, variant: 0).fingerprints.map(\.fingerprint), ["aumu/EZk2/Toon"])
    }

    func testUnknownVariantThrowsProjectDataMissing() throws {
        let bundle = try twoVariantBundle()
        XCTAssertThrowsError(try ProjectParser.parse(bundle: bundle, variant: 7)) {
            XCTAssertEqual($0 as? ParseError, .projectDataMissing(bundle.path))
        }
    }

    func testSummaryCarriesAlternativesAndLastSavedFrom() throws {
        let s = try ProjectParser.parse(bundle: try twoVariantBundle())
        XCTAssertEqual(s.alternatives.map(\.displayName), ["Main", "Alt"])
        XCTAssertEqual(s.lastSavedFrom, "Logic Pro 12.2 (6644)")
        XCTAssertEqual(s.variant, 0)
    }

    func testDefaultParseUsesLowestAvailableVariant() throws {
        let bundle = try twoVariantBundle()
        XCTAssertEqual(try ProjectParser.parse(bundle: bundle).variant, 0)
    }
}
