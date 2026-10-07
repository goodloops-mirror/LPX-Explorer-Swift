import XCTest
@testable import LpxCore

final class RegionsTests: XCTestCase {
    static let marker: [UInt8] = [0x61, 0xff] + [UInt8](repeating: 0, count: 24)

    static func region(_ name: String, length: Int? = nil) -> [UInt8] {
        let len = length ?? name.utf8.count
        return [0x01, 0x02, 0x03, 0x04] + marker + [UInt8(len & 0xff), UInt8(len >> 8)] + Array(name.utf8)
    }

    func testFindsSingleRegionRecord() {
        let bytes = Self.region("Vocal")
        let found = Regions.findRecords(bytes)
        XCTAssertEqual(found, [RegionRecord(offset: 4, name: "Vocal")])
    }

    func testRejectsZeroLengthAndOversizeNames() {
        XCTAssertTrue(Regions.findRecords(Self.region("", length: 0)).isEmpty)
        XCTAssertTrue(Regions.findRecords(Self.region(String(repeating: "A", count: 201))).isEmpty)
    }

    func testRejectsNonPrintableNameBytes() {
        var bytes = Self.region("Vocal")
        bytes[bytes.count - 1] = 0x01
        XCTAssertTrue(Regions.findRecords(bytes).isEmpty)
    }

    func testFindsMultipleRecordsInOffsetOrder() {
        let bytes = Self.region("A one") + Self.region("B two")
        XCTAssertEqual(Regions.findRecords(bytes).map(\.name), ["A one", "B two"])
    }

    private func recs(_ names: [String]) -> [RegionRecord] { names.enumerated().map { RegionRecord(offset: $0.offset * 100, name: $0.element) } }

    func testClusterGroupsConsecutiveSameNamedRecords() {
        let c = Regions.cluster(recs(["Vocal", "Vocal", "Vocal"]))
        XCTAssertEqual(c, [RegionCluster(baseName: "Vocal", firstOffset: 0, lastOffset: 200, count: 3)])
    }

    func testClusterStartsNewClusterWhenNameChanges() {
        XCTAssertEqual(Regions.cluster(recs(["Vocal", "Vocal", "Guitar"])).map(\.baseName), ["Vocal", "Guitar"])
    }

    func testClusterStripsTakeAndCompSuffixes() {
        let c = Regions.cluster(recs(["Vocal: Take 14.1", "Vocal: Comp A", "Vocal #06", "Vocal.2", "Vocal - Take 3"]))
        XCTAssertEqual(c.map(\.baseName), ["Vocal"])
        XCTAssertEqual(c.first?.count, 5)
    }

    func testClusterDropsRecordingFilenamesAndBareCompTags() {
        let c = Regions.cluster(recs(["Comp A", "Audio_12", "Audio_12 #3", "Vocal"]))
        XCTAssertEqual(c.map(\.baseName), ["Vocal"])
    }

    func testIsAutoTrackNameMatchesDefaultChannelStripNames() {
        for n in ["Audio 1", "Inst 12", "Bus 7", "Aux 2", "Output 1-2", "Input 3", "Master", "Audio"] {
            XCTAssertTrue(Regions.isAutoTrackName(n), n)
        }
    }

    func testIsAutoTrackNameRejectsUserRenames() {
        for n in ["Lead Vox", "Audio 1 copy", "Audio1", "Audio ", "Audio 1-", "Kick 1", "audio 1", ""] {
            XCTAssertFalse(Regions.isAutoTrackName(n), n)
        }
    }
}
