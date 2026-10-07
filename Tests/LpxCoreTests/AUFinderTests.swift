import XCTest
@testable import LpxCore

final class AUFinderTests: XCTestCase {
    /// Mirrors the Rust fixture: name padding, then manufacturer | type | subtype,
    /// each 4CC little-endian (so "Toon" is stored as "nooT").
    func testFindsSingleInstrumentDescriptor() {
        let bytes = Array("PADDING_".utf8) + Array("nooT".utf8) + Array("umua".utf8) + Array("2kZE".utf8)

        let found = AUFinder.findAUs(bytes)

        XCTAssertEqual(found.count, 1)
        XCTAssertEqual(found.first?.typeCode, "aumu")
        XCTAssertEqual(found.first?.subtype, "EZk2")
        XCTAssertEqual(found.first?.manufacturer, "Toon")
        XCTAssertEqual(found.first?.offset, 12)
        XCTAssertEqual(found.first?.fingerprint, "aumu/EZk2/Toon")
    }

    func testFindsAumiMidiProcessorDescriptor() {
        let bytes = Array("PADDING_".utf8) + Array("eMai".utf8) + Array("imua".utf8) + Array("cl2S".utf8)

        let found = AUFinder.findAUs(bytes)

        XCTAssertEqual(found.map(\.fingerprint), ["aumi/S2lc/iaMe"])
    }

    /// Binary noise contains planted type tags whose neighbours are non-printable;
    /// only the real descriptor (aufx/Comp/Yamh at offset 24) may be returned.
    func testRejectsDescriptorsWithNonPrintable4CCs() {
        var bytes: [UInt8] = [0x00, 0xFF, 0x01, 0x7F]
        bytes += Array("umua".utf8)
        bytes += [0xFE, 0x00, 0x10, 0x7F]
        bytes += Array("PAD_".utf8)
        bytes += Array("NAME".utf8) + Array("hmaY".utf8) + Array("xfua".utf8) + Array("pmoC".utf8)
        bytes += [0x00, 0x01, 0x02, 0x03] + Array("xfua".utf8) + [0xFF, 0xFE, 0xFD, 0xFC] + [0xAA, 0xBB, 0xCC, 0xDD]

        let found = AUFinder.findAUs(bytes)

        XCTAssertEqual(found.map(\.fingerprint), ["aufx/Comp/Yamh"])
        XCTAssertEqual(found.first?.offset, 24)
    }

    // MARK: text blobs (base64 etc.)

    /// Plist/base64 blobs embedded in ProjectData are pure printable text, so a type tag can
    /// occur by chance with printable "4CCs" on both sides. On real projects every such hit was
    /// noise: real descriptors have binary structure around them.
    func testRejectsTagsInsidePrintableTextBlobs() {
        let blob = Array("Zm9vYmFyYmF6\n\txdYQ".utf8) + Array("nooT".utf8) + Array("fmua".utf8) + Array("2kZE".utf8) + Array("QmFzZTY0\n\tdGV4dA".utf8)
        XCTAssertTrue(AUFinder.findAUs(blob).isEmpty)
    }

    func testKeepsDescriptorWithBinaryAfterItEvenIfNamePaddingBeforeItIsText() {
        let real = Array("Pro-Q 3  ".utf8) + Array("FbaF".utf8) + Array("fmua".utf8) + Array("p3QF".utf8) + [0x00, 0x00, 0xff, 0xff, 0, 0, 0, 0]
        XCTAssertEqual(AUFinder.findAUs(real).map(\.fingerprint), ["aumf/FQ3p/FabF"])
    }

    func testKeepsDescriptorWithBinaryBeforeItEvenIfTextFollows() {
        let real = [0x00, 0x01, 0x02, 0x03, 0x00, 0x00, 0x00, 0x00] + Array("FbaF".utf8) + Array("fmua".utf8) + Array("p3QF".utf8) + Array("ABCDEFGH".utf8)
        XCTAssertEqual(AUFinder.findAUs(real).count, 1)
    }

    func testDescriptorAtVeryEndOfBufferIsStillAccepted() {
        let tail = Array("PADDING_".utf8) + Array("nooT".utf8) + Array("umua".utf8) + Array("2kZE".utf8)
        XCTAssertEqual(AUFinder.findAUs(tail).count, 1)
    }
}
