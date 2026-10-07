import XCTest
@testable import LpxCore

final class TrackRegistryTests: XCTestCase {
    /// `0000 SIG b6-9 ctrl ctrl 0000 LENLO 00 NAME TRAILER`, optionally preceded by the
    /// 62-byte "track-link" preamble whose first u16 is the track id.
    private func record(_ sig: [UInt8], _ name: String, trailer: [UInt8] = [UInt8](repeating: 0, count: 8),
                        link: UInt16? = nil, bytes69: [UInt8] = [0, 0, 0, 0]) -> [UInt8] {
        var buf: [UInt8] = []
        if let id = link { buf += [UInt8(id & 0xff), UInt8(id >> 8)] + [UInt8](repeating: 0, count: 60) }
        buf += [0, 0, 0, 0]
        buf += sig
        buf += bytes69
        buf += [0xAB, 0xCD, 0, 0]
        buf += [UInt8(name.utf8.count), 0]
        buf += Array(name.utf8)
        buf += trailer
        return buf
    }

    func testFindsInstrumentAndAudioRecords() {
        XCTAssertEqual(TrackRegistry.findRecords(record([0x22, 0x12], "Piano")).first?.kind, .instrument)
        XCTAssertEqual(TrackRegistry.findRecords(record([0x23, 0x12], "Vocals")).first?.kind, .audio)
    }

    func testEachWhitelistedSignatureMapsToItsKind() {
        let table: [([UInt8], TrackKind)] = [
            ([0x22, 0x12], .instrument), ([0xa8, 0x11], .instrument), ([0xda, 0x11], .instrument), ([0xe7, 0x10], .instrument),
            ([0x03, 0x10], .instrument), ([0x4d, 0x10], .instrument), ([0x5f, 0x11], .instrument),
            ([0x23, 0x12], .audio), ([0xdc, 0x11], .audio), ([0xdf, 0x11], .audio), ([0x47, 0x11], .audio),
            ([0xc7, 0x10], .audio), ([0x4c, 0x10], .audio), ([0x9a, 0x11], .audio), ([0x7a, 0x11], .audio),
            ([0x74, 0x10], .folder), ([0xcb, 0x10], .folder), ([0xe3, 0x11], .folder), ([0xe4, 0x10], .folder),
            ([0xeb, 0x11], .folder), ([0xe7, 0x11], .folder), ([0x0d, 0x10], .folder), ([0x8d, 0x11], .folder),
        ]
        for (sig, kind) in table { XCTAssertEqual(TrackRegistry.findRecords(record(sig, "Name")).first?.kind, kind, "\(sig)") }
    }

    func testAcceptsFFFF0000VariantHeader() {
        XCTAssertEqual(TrackRegistry.findRecords(record([0x03, 0x10], "Piano", bytes69: [0xff, 0xff, 0, 0])).count, 1)
    }

    func testAcceptsNonZeroByte6WhenBytes7To9AreZero() {
        XCTAssertEqual(TrackRegistry.findRecords(record([0x4d, 0x10], "Bass", bytes69: [0x6c, 0, 0, 0])).count, 1)
    }

    func testRejectsNonZeroBytes7To9() {
        XCTAssertTrue(TrackRegistry.findRecords(record([0x22, 0x12], "Piano", bytes69: [0, 0x01, 0, 0])).isEmpty)
    }

    func testIgnoresUnknownSignaturesAndNoiseNames() {
        XCTAssertTrue(TrackRegistry.findRecords(record([0x99, 0x99], "Piano")).isEmpty)
        for noise in ["Master", "Click", "Unused", "VCA 1", "(Folder)"] {
            XCTAssertTrue(TrackRegistry.findRecords(record([0x22, 0x12], noise)).isEmpty, noise)
        }
        XCTAssertEqual(TrackRegistry.findRecords(record([0x22, 0x12], "Untitled")).count, 1)
    }

    func testRejectsNonPrintableNameAndHighLengthByte() {
        var bad = record([0x22, 0x12], "Piano")
        bad[bad.count - 8 - 1] = 0x01
        XCTAssertTrue(TrackRegistry.findRecords(bad).isEmpty)
        var hi = record([0x22, 0x12], "Piano")
        hi[15] = 1
        XCTAssertTrue(TrackRegistry.findRecords(hi).isEmpty)
    }

    func testSummingStackTrailerUpgradesFolderKind() {
        let stack = TrackRegistry.findRecords(record([0x74, 0x10], "Sub 1", trailer: [0x55, 0x01, 0x00, 0x01, 0x00, 0x01, 0, 0]))
        XCTAssertEqual(stack.first?.kind, .summingStack)
        let plain = TrackRegistry.findRecords(record([0x74, 0x10], "Sub 1", trailer: [0x55, 0x00, 0x00, 0xff, 0x00, 0x01, 0, 0]))
        XCTAssertEqual(plain.first?.kind, .folder)
        let skipped = TrackRegistry.findRecords(record([0x74, 0x10], "Sub 1", trailer: [0x00, 0x55, 0x01, 0x00, 0x01, 0x00, 0x01, 0]))
        XCTAssertEqual(skipped.first?.kind, .summingStack)
    }

    func testTrackIDComesFromPrecedingLinkStructure() {
        XCTAssertEqual(TrackRegistry.findRecords(record([0x23, 0x12], "Vocals", link: 0x1234)).first?.trackID, 0x1234)
        XCTAssertEqual(TrackRegistry.findRecords(record([0x23, 0x12], "Vocals")).first?.trackID, 0)
    }

    func testStripIDForAudioInstrumentAndFallbackOffset() {
        XCTAssertEqual(TrackRegistry.findRecords(record([0x23, 0x12], "Vocals", trailer: [5, 0, 0, 0, 0, 0, 0, 0])).first?.stripID, 5)
        XCTAssertEqual(TrackRegistry.findRecords(record([0x22, 0x12], "Piano", trailer: [53, 0, 0, 0, 0, 0, 0, 0])).first?.stripID, 53)
        XCTAssertEqual(TrackRegistry.findRecords(record([0x23, 0x12], "Vocals", trailer: [0, 7, 0, 0, 0, 0, 0, 0])).first?.stripID, 7)
        XCTAssertEqual(TrackRegistry.findRecords(record([0x74, 0x10], "Sub", trailer: [5, 0, 0, 0, 0, 0, 0, 0])).first?.stripID, 0)
    }

    func testEmptyInputAndOrdering() {
        XCTAssertTrue(TrackRegistry.findRecords([]).isEmpty)
        let both = record([0x22, 0x12], "Piano") + record([0x23, 0x12], "Vocals")
        XCTAssertEqual(TrackRegistry.findRecords(both).map(\.name), ["Piano", "Vocals"])
    }
}
