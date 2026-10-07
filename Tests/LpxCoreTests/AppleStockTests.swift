import XCTest
@testable import LpxCore

final class AppleStockTests: XCTestCase {
    private let fxFirst: UInt8 = 0x02, instrumentFirst: UInt8 = 0x00, fxFlag2: UInt8 = 0x02
    private let marker = Array("GAME".utf8)

    private func record(_ flag1: UInt8, _ name: String, trailer: [UInt8] = [UInt8](repeating: 0, count: 8), flag2: UInt8 = 0x02) -> [UInt8] {
        var buf = [UInt8](repeating: 0, count: 8)
        buf += [flag1, flag2]
        buf += Array(name.utf8)
        buf += [UInt8](repeating: 0, count: 12 - name.utf8.count)
        return buf + marker + trailer
    }

    func testFindsAudioFxSlot() {
        let found = AppleStock.findAUs(record(fxFirst, "Compressor"))
        XCTAssertEqual(found.count, 1)
        XCTAssertEqual(found.first?.typeCode, "aufx")
        XCTAssertEqual(found.first?.manufacturer, "appl")
        XCTAssertEqual(found.first?.displayName, "Compressor")
    }

    func testFindsInstrumentSlot() {
        let found = AppleStock.findAUs(record(instrumentFirst, "Alchemy"))
        XCTAssertEqual(found.first?.typeCode, "aumu")
        XCTAssertEqual(found.first?.displayName, "Alchemy")
    }

    func testRejectsUnrecognisedFirstFlag() {
        XCTAssertTrue(AppleStock.findAUs(record(0xff, "Compressor")).isEmpty)
    }

    func testRejectsNonZeroPaddingAfterName() {
        var buf = [UInt8](repeating: 0, count: 8) + [fxFirst, fxFlag2] + Array("Hi".utf8)
        buf += [UInt8](repeating: 0xff, count: 10) + marker
        XCTAssertTrue(AppleStock.findAUs(buf).isEmpty)
    }

    func testRejectsWrongSecondFlagByte() {
        XCTAssertTrue(AppleStock.findAUs(record(fxFirst, "Compressor", flag2: 0x05)).isEmpty)
    }

    func testRejectsEmptyNameField() {
        XCTAssertTrue(AppleStock.findAUs(record(fxFirst, "")).isEmpty)
    }

    func testSkipsGarbageGameBytesInRealisticBlob() {
        var buf = [UInt8](repeating: 0xff, count: 14) + marker
        buf += record(fxFirst, "Limiter", trailer: [0, 0, 0, 0])
        buf += [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13] + marker
        buf += record(instrumentFirst, "Alchemy", trailer: [0, 0, 0, 0])

        XCTAssertEqual(AppleStock.findAUs(buf).compactMap(\.displayName), ["Limiter", "Alchemy"])
    }

    func testSynthSubtypeIsDeterministicAndFourChars() {
        XCTAssertEqual(AppleStock.synthSubtype("Compressor"), "comp")
        XCTAssertEqual(AppleStock.synthSubtype("Bass Amp"), "bass")
        XCTAssertEqual(AppleStock.synthSubtype("Graph EQ"), "grap")
        XCTAssertEqual(AppleStock.synthSubtype("Hi"), "hixx")
        XCTAssertEqual(AppleStock.synthSubtype(""), "xxxx")
    }

    func testKnownNameYieldsRealAuvalFingerprint() {
        XCTAssertEqual(AppleStock.findAUs(record(fxFirst, "Compressor")).first?.fingerprint, "aufx/Comp/appl")
    }

    func testUnknownNameFallsBackToSynthesisedFingerprint() {
        XCTAssertEqual(AppleStock.findAUs(record(fxFirst, "MysteryAU")).first?.fingerprint, "aufx/myst/appl")
    }

    func testTableTypeWinsOverFlagByte() {
        let au = AppleStock.findAUs(record(instrumentFirst, "Compressor")).first
        XCTAssertEqual(au?.typeCode, "aufx")
        XCTAssertEqual(au?.subtype, "Comp")
    }

    func testFindsKlopfgeistWithFlag2One() {
        let au = AppleStock.findAUs(record(instrumentFirst, "Klopfgeist", flag2: 0x01)).first
        XCTAssertEqual(au?.fingerprint, "aumu/klop/appl")
        XCTAssertEqual(au?.displayName, "Klopfgeist")
    }

    func testStockLookupIsCaseSensitive() {
        XCTAssertEqual(AppleStock.lookupStockFingerprint("Compressor")?.subtype, "Comp")
        XCTAssertNil(AppleStock.lookupStockFingerprint("compressor"))
        XCTAssertNil(AppleStock.lookupStockFingerprint("COMPRESSOR"))
    }

    func testOffsetPointsAtNameFieldStart() {
        XCTAssertEqual(AppleStock.findAUs(record(fxFirst, "Compressor")).first?.offset, 10)
    }

    /// findAUs must include stock records alongside 4CC triples, sorted by offset.
    func testFindAUsMergesStockAndStandardDescriptorsByOffset() {
        let triple = Array("PADDING_".utf8) + Array("nooT".utf8) + Array("umua".utf8) + Array("2kZE".utf8)
        let bytes = triple + record(fxFirst, "Limiter")

        let found = AUFinder.findAUs(bytes)

        XCTAssertEqual(found.map(\.fingerprint), ["aumu/EZk2/Toon", "aufx/limi/appl"])
        XCTAssertEqual(found.map(\.offset), found.map(\.offset).sorted())
    }
}
