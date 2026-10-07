import XCTest
@testable import LpxCore

final class AppleDrummerTests: XCTestCase {
    private let key = Array(#""selectedPersistentCharacterTypeIdentifier":""#.utf8)

    private func blob(_ character: String, _ typeID: String) -> [UInt8] {
        Array(#"{"selectedCharacterIdentifier":"\#(character)","selectedPersistentCharacterTypeIdentifier":"\#(typeID)"}"#.utf8)
    }

    func testFindsSingleInstance() {
        let found = AppleDrummer.findAUs(blob("Electric Bass - Pop Songwriter", "Type_ElectricBassV2"))
        XCTAssertEqual(found.count, 1)
        XCTAssertEqual(found.first?.typeCode, "aumu")
        XCTAssertEqual(found.first?.manufacturer, "appl")
        XCTAssertEqual(found.first?.displayName, "Bass Player")
    }

    func testClusteredSnapshotsCollapseToLatestCharacter() {
        var buf: [UInt8] = []
        for _ in 0..<5 { buf += blob("Acoustic Drummer - Pop Rock", "Type_AcousticDrummerV2") }
        buf += blob("Electric Bass - Pop Songwriter", "Type_ElectricBassV2")

        let found = AppleDrummer.findAUs(buf)

        XCTAssertEqual(found.count, 1)
        XCTAssertEqual(found.first?.displayName, "Bass Player")
    }

    func testFarApartClustersStaySeparate() {
        var buf = blob("Acoustic Drummer - Pop Rock", "Type_AcousticDrummerV2")
        buf += [UInt8](repeating: 0, count: AppleDrummer.clusterThreshold + 100)
        buf += blob("Electric Bass - Pop Songwriter", "Type_ElectricBassV2")

        XCTAssertEqual(AppleDrummer.findAUs(buf).compactMap(\.displayName), ["Drummer", "Bass Player"])
    }

    func testIgnoresValueWithoutTypePrefix() {
        XCTAssertTrue(AppleDrummer.findAUs(Array(#"{"selectedPersistentCharacterTypeIdentifier":"GarbledNoise"}"#.utf8)).isEmpty)
    }

    func testIgnoresTruncatedValueWithNoClosingQuote() {
        let bytes = key + Array("Type_".utf8) + [UInt8](repeating: UInt8(ascii: "A"), count: AppleDrummer.maxTypeValueLen)
        XCTAssertTrue(AppleDrummer.findAUs(bytes).isEmpty)
    }

    func testUnknownCharacterFallsBackToStrippedTypeID() {
        XCTAssertEqual(AppleDrummer.findAUs(blob("?", "Type_FutureCharacterV9")).first?.displayName, "FutureCharacterV9")
    }

    func testEmptyWhenNoDrummerStatePresent() {
        XCTAssertTrue(AppleDrummer.findAUs(Array("some unrelated binary content with no drummer JSON anywhere".utf8)).isEmpty)
    }

    func testClusterOffsetPointsAtFirstMatchInCluster() {
        let first = blob("Acoustic Drummer - Pop Rock", "Type_AcousticDrummerV2")
        let buf = [UInt8](repeating: 0, count: 100) + first + blob("Electric Bass - Pop Songwriter", "Type_ElectricBassV2")
        let keyInFirst = (0...(first.count - key.count)).first { Array(first[$0 ..< $0 + key.count]) == key }!

        XCTAssertEqual(AppleDrummer.findAUs(buf).first?.offset, 100 + keyInFirst)
    }

    func testFindAUsIncludesDrummer() {
        let buf = blob("Acoustic Drummer - Pop Rock", "Type_AcousticDrummerV2")
        XCTAssertEqual(AUFinder.findAUs(buf).map(\.fingerprint), ["aumu/drum/appl"])
    }
}
