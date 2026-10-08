import XCTest
@testable import LpxCore

enum ArrangementFixture {
    static func u32(_ v: UInt32) -> [UInt8] { (0..<4).map { UInt8((v >> (8 * UInt32($0))) & 0xff) } }

    /// A 93-byte track record (92 bytes and record version 4 when `older`, as written by Logic Pro X 10.5 and earlier).
    /// `type` 1 = ordinary track, 3 = the output ("Stereo Out") record.
    static func record(index: UInt32, nameID: UInt32 = 0, key: UInt32, type: UInt8 = 1, hidden: Bool = false, older: Bool = false) -> [UInt8] {
        var r = [UInt8](repeating: 0, count: older ? 92 : 93)
        r.replaceSubrange(4..<8, with: Array("karT".utf8))
        r.replaceSubrange(8..<18, with: [older ? 0x04 : 0x05, 0, 0x17, 0, 0, 0, 0x04, 0, 0, 0])
        r.replaceSubrange(18..<22, with: [0xff, 0xff, 0xff, 0xff])
        r.replaceSubrange(22..<26, with: u32(index))
        r.replaceSubrange(26..<40, with: [2, 0, 0, 0, 2, 0, 0x39, 0, 0, 0, 0, 0, 0, 0])
        r.replaceSubrange(40..<44, with: [type, 0, 0x14, hidden ? 0x04 : 0x00])
        r.replaceSubrange(44..<48, with: u32(nameID))
        r.replaceSubrange(48..<52, with: u32(key))
        for k in 64..<80 { r[k] = UInt8(0xA0 + (k & 0x0f)) } // uuid
        return r
    }

    /// qSxT text object: header, size at +28, text at +134, NUL-terminated.
    static func text(id: UInt32, _ s: String, terminated: Bool = true) -> [UInt8] {
        let body = Array(s.utf8) + (terminated ? [0] : [])
        var r = [UInt8](repeating: 0, count: 134)
        r.replaceSubrange(0..<4, with: Array("qSxT".utf8))
        r.replaceSubrange(4..<10, with: [0x01, 0, 0x20, 0, 0, 0])
        r.replaceSubrange(10..<14, with: u32(id))
        r.replaceSubrange(14..<22, with: [UInt8](repeating: 0xff, count: 8))
        r.replaceSubrange(22..<28, with: [2, 0, 0, 0, 2, 0])
        r.replaceSubrange(28..<32, with: u32(UInt32(body.count + 99)))
        return [UInt8](repeating: 0, count: 12) + r + body
    }
}

final class ArrangementListTests: XCTestCase {
    private typealias F = ArrangementFixture
    private let noise = [UInt8](repeating: 0x11, count: 50)

    func testReadsTracksInOrderWithPositionsNamesKeysAndHiddenFlag() {
        let raw = noise
            + F.record(index: 0, key: 0x170) + F.record(index: 1, nameID: 0x3c, key: 0x10, hidden: true) + F.record(index: 2, nameID: 0x50, key: 0x9c)
            + F.record(index: 3, nameID: 0x30, key: 0x50, type: 3)
            + noise
        let r = ArrangementList.records(raw)
        XCTAssertEqual(r.map(\.position), [1, 2, 3])
        XCTAssertEqual(r.map(\.objectKey), [0x170, 0x10, 0x9c])
        XCTAssertEqual(r.map(\.nameTextID), [0, 0x3c, 0x50])
        XCTAssertEqual(r.map(\.isHidden), [false, true, false])
    }

    func testOlderFilesWithNinetyTwoByteRecordsReadTheSame() {
        func list(older: Bool) -> [ArrangementRecord] {
            ArrangementList.records(noise
                + ArrangementFixture.record(index: 0, key: 0x170, older: older)
                + ArrangementFixture.record(index: 1, nameID: 0x3c, key: 0x10, hidden: true, older: older)
                + ArrangementFixture.record(index: 2, nameID: 0x50, key: 0x9c, older: older)
                + ArrangementFixture.record(index: 3, nameID: 0x30, key: 0x50, type: 3, older: older)
                + noise)
        }
        let older = list(older: true), newer = list(older: false)
        XCTAssertEqual(newer.map(\.position), [1, 2, 3])
        XCTAssertEqual(older.map(\.position), newer.map(\.position))
        XCTAssertEqual(older.map(\.nameTextID), newer.map(\.nameTextID))
        XCTAssertEqual(older.map(\.objectKey), newer.map(\.objectKey))
        XCTAssertEqual(older.map(\.isHidden), newer.map(\.isHidden))
    }

    func testTheLongerRunWinsWhenBothSpacingsOccur() {
        // A short run of the other spacing elsewhere in the file must not hide the real list.
        let real = (0..<6).flatMap { ArrangementFixture.record(index: UInt32($0), key: UInt32(0x100 + $0), older: true) }
        let stray = (0..<2).flatMap { ArrangementFixture.record(index: UInt32($0), key: 9) }
        XCTAssertEqual(ArrangementList.records(noise + stray + noise + real + noise).count, 6)
        XCTAssertEqual(ArrangementList.records(noise + real + noise + stray + noise).count, 6)
    }

    func testOutputRecordAndSentinelAreNotTracks() {
        let raw = noise + F.record(index: 0, key: 0x68) + F.record(index: 1, nameID: 0x30, key: 0x50, type: 3) + F.record(index: 0x7fff_ffff, key: 0x40000) + noise
        XCTAssertEqual(ArrangementList.records(raw).map(\.position), [1])
    }

    func testSeveralTracksMayShareAnObjectKey() {
        let raw = noise + F.record(index: 0, nameID: 0xc, key: 0x218) + F.record(index: 1, nameID: 0x1c, key: 0x218)
        let r = ArrangementList.records(raw)
        XCTAssertEqual(r.map(\.objectKey), [0x218, 0x218])
        XCTAssertEqual(r.map(\.nameTextID), [0xc, 0x1c])
    }

    func testChoosesTheRunStartingAtIndexZeroNotAnEarlierShortRun() {
        let stray = F.record(index: 4, key: 0x999)             // a lone id-4 object elsewhere in the file
        let raw = stray + noise + F.record(index: 0, key: 0x1) + F.record(index: 1, key: 0x2) + F.record(index: 2, key: 0x3)
        XCTAssertEqual(ArrangementList.records(raw).map(\.objectKey), [1, 2, 3])
    }

    func testRunWithBrokenIndexSequenceStopsAtTheBreak() {
        let raw = noise + F.record(index: 0, key: 1) + F.record(index: 1, key: 2) + F.record(index: 5, key: 3)
        XCTAssertEqual(ArrangementList.records(raw).map(\.objectKey), [1, 2])
    }

    func testNoListMeansEmpty() {
        XCTAssertTrue(ArrangementList.records([]).isEmpty)
        XCTAssertTrue(ArrangementList.records(noise).isEmpty)
        XCTAssertTrue(ArrangementList.records(Array(F.record(index: 0, key: 1).prefix(60))).isEmpty, "truncated record")
    }

    func testRecordOffsetPointsAtTheTag() {
        let raw = noise + F.record(index: 0, key: 1)
        XCTAssertEqual(ArrangementList.records(raw).first?.offset, noise.count + 4)
    }
}

final class NameTextsTests: XCTestCase {
    private typealias F = ArrangementFixture

    func testReadsTextsById() {
        let raw = F.text(id: 0x10, "CUE") + F.text(id: 0x4, "SYNTHS MALLETS")
        XCTAssertEqual(NameTexts.find(raw), [0x10: "CUE", 0x4: "SYNTHS MALLETS"])
    }

    func testStripsTrailingNULsAndKeepsUTF8() {
        XCTAssertEqual(NameTexts.find(F.text(id: 8, "Café ☕️"))[8], "Café ☕️")
        let padded = F.text(id: 9, "SYNTHS") // size counts the terminator
        XCTAssertEqual(NameTexts.find(padded)[9], "SYNTHS")
    }

    func testNotesAndGarbageAreIgnored() {
        let rtf = F.text(id: 1, "{\\rtf1\\ansi\\ansicpg1252 hello}")
        let slashes = F.text(id: 2, "//QR junk")
        let ctrl = F.text(id: 3, "bad\u{01}text")
        XCTAssertTrue(NameTexts.find(rtf + slashes + ctrl).isEmpty)
    }

    func testTruncatedRecordIsSafe() {
        XCTAssertTrue(NameTexts.find(Array(F.text(id: 1, "Hello").prefix(100))).isEmpty)
        XCTAssertTrue(NameTexts.find([]).isEmpty)
    }
}

final class TrackObjectsTests: XCTestCase {
    private typealias F = ArrangementFixture

    /// 170 header bytes (key at 0 and 42) + registry-shaped record of class `cls`.
    private func object(name: String, cls: UInt16, key: UInt32, stripID: UInt8, leading: [UInt8] = [0, 0]) -> [UInt8] {
        var head = [UInt8](repeating: 0x11, count: 170)
        head.replaceSubrange(0..<4, with: F.u32(key)); head.replaceSubrange(42..<46, with: F.u32(key))
        let rec: [UInt8] = leading + [0, 0, UInt8(cls & 0xff), UInt8(cls >> 8), 0, 0, 0, 0, 0xAB, 0xCD, 0, 0, UInt8(name.utf8.count), 0]
        return head + rec + Array(name.utf8) + [stripID, 0, 0, 0, 0, 1, 0, 0]
    }

    func testFindsObjectsOfAnyClass() {
        let raw = object(name: "DX", cls: 0x1223, key: 0x170, stripID: 1) + object(name: "Harp 1", cls: 0x1199, key: 0x1c8, stripID: 143)
            + object(name: "flute", cls: 0x11f4, key: 0x204, stripID: 4)
        let found = TrackObjects.find(raw)
        XCTAssertEqual(found.map(\.name), ["DX", "Harp 1", "flute"])
        XCTAssertEqual(found.map(\.key), [0x170, 0x1c8, 0x204])
        XCTAssertEqual(found.map(\.classNumber), [0x1223, 0x1199, 0x11f4])
        XCTAssertEqual(found.map(\.stripID), [1, 143, 4])
    }

    func testBothAlignmentsOfTheStripNumberAreKept() {
        // trailer `00 01 00 …`: read at +0 it is 0x0100 (256), at +1 it is 1 — the real one
        var raw = object(name: "TRACKNAME AUDIO 1", cls: 0x1223, key: 0x58, stripID: 0)
        raw.replaceSubrange((raw.count - 8)..<raw.count, with: [0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00])
        let found = TrackObjects.find(raw).first
        XCTAssertEqual(found?.stripID, 256)
        XCTAssertEqual(found?.altStripID, 1)
    }

    func testUnambiguousStripNumberHasNoAlternative() {
        let found = TrackObjects.find(object(name: "DX", cls: 0x1223, key: 0x170, stripID: 1)).first
        XCTAssertEqual(found?.stripID, 1)
        XCTAssertEqual(found?.altStripID, 0)
    }

    func testRecordsWithoutAConsistentKeyAreSkipped() {
        var raw = object(name: "DX", cls: 0x1223, key: 0x170, stripID: 1)
        raw.replaceSubrange(42..<46, with: F.u32(0x999))
        XCTAssertTrue(TrackObjects.find(raw).isEmpty)
        XCTAssertTrue(TrackObjects.find(object(name: "Zero", cls: 0x1223, key: 0, stripID: 1)).isEmpty)
    }

    // MARK: older files: the record starts right behind the previous text

    func testLenientModeAcceptsRecordsPackedBehindText() {
        let raw = object(name: "soft piano", cls: 0x1199, key: 0x94, stripID: 3, leading: Array("of".utf8))
        XCTAssertTrue(TrackObjects.find(raw).isEmpty, "strict: the record must start with four zero bytes")
        XCTAssertEqual(TrackObjects.find(raw, lenient: true).map(\.name), ["soft piano"])
        XCTAssertEqual(TrackObjects.find(raw, lenient: true).first?.key, 0x94)
    }

    func testLenientModeStillNeedsTheKeyAndTheRestOfTheShape() {
        var noKey = object(name: "x", cls: 0x1199, key: 0x94, stripID: 3, leading: Array("of".utf8))
        noKey.replaceSubrange(42..<46, with: F.u32(0x1))
        XCTAssertTrue(TrackObjects.find(noKey, lenient: true).isEmpty)
        var badShape = object(name: "x", cls: 0x1199, key: 0x94, stripID: 3, leading: [1, 1])
        badShape.replaceSubrange(172..<174, with: [9, 9])          // bytes 2-3 of the record are not zero
        XCTAssertTrue(TrackObjects.find(badShape, lenient: true).isEmpty)
    }

    func testCompleteAddsLenientMatchesOnlyForKeysTheStrictPassMissed() {
        let raw = (object(name: "DX", cls: 0x1223, key: 0x170, stripID: 1)
                   + object(name: "soft piano", cls: 0x1199, key: 0x94, stripID: 3, leading: Array("of".utf8))).withUnsafeBufferPointer { buf -> [ObjectRecord] in
            let strict = TrackObjects.find(in: buf)
            XCTAssertEqual(strict.map(\.name), ["DX"])
            return TrackObjects.complete(strict, needing: [0x170, 0x94], in: buf)
        }
        XCTAssertEqual(raw.map(\.name), ["DX", "soft piano"])
    }

    func testCompleteLeavesFilesAloneWhenEverythingWasFoundStrictly() {
        let data = object(name: "DX", cls: 0x1223, key: 0x170, stripID: 1) + object(name: "late", cls: 0x1199, key: 0x94, stripID: 3, leading: Array("of".utf8))
        data.withUnsafeBufferPointer { buf in
            let strict = TrackObjects.find(in: buf)
            XCTAssertEqual(TrackObjects.complete(strict, needing: [0x170], in: buf), strict, "0x94 is not needed, so the lenient pass is not even run")
            XCTAssertEqual(TrackObjects.complete(strict, needing: [], in: buf), strict)
        }
    }
}
