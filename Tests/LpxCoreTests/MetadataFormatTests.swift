import XCTest
@testable import LpxCore

final class MetadataFormatTests: XCTestCase {
    func testFrameRateTableMatchesTheOriginalApp() {
        let expected = [0: "24 fps", 1: "25 fps", 2: "29.97 fps (drop)", 3: "30 fps (drop)", 4: "29.97 fps", 5: "30 fps", 6: "23.976 fps", 7: "23.976 fps"]
        for (index, label) in expected { XCTAssertEqual(MetadataFormat.frameRate(index: index), label, "index \(index)") }
        XCTAssertNil(MetadataFormat.frameRate(index: 8))
        XCTAssertNil(MetadataFormat.frameRate(index: -1))
    }

    func testSampleRateInKilohertz() {
        XCTAssertEqual(MetadataFormat.sampleRate(hz: 48000), "48.0 kHz")
        XCTAssertEqual(MetadataFormat.sampleRate(hz: 44100), "44.1 kHz")
        XCTAssertEqual(MetadataFormat.sampleRate(hz: 96000), "96.0 kHz")
        XCTAssertEqual(MetadataFormat.sampleRate(hz: 0), "—")
    }

    func testKeyWithModeOrWithout() {
        XCTAssertEqual(MetadataFormat.key("C", gender: "major"), "C major")
        XCTAssertEqual(MetadataFormat.key("F#", gender: "Minor"), "F# minor")
        XCTAssertEqual(MetadataFormat.key("D", gender: "?"), "D")
        XCTAssertEqual(MetadataFormat.key("D", gender: ""), "D")
        XCTAssertNil(MetadataFormat.key("?", gender: "major"))
        XCTAssertNil(MetadataFormat.key("", gender: ""))
    }

    func testDateWithRelativeAge() {
        let en = Locale(identifier: "en_US")
        let now = Date(timeIntervalSince1970: 1_791_450_000)           // 2026-10-08
        let threeDaysAgo = Int64(now.timeIntervalSince1970) - 3 * 86_400
        let text = MetadataFormat.dateWithRelative(unix: threeDaysAgo, now: now, locale: en)
        XCTAssertTrue(text.hasPrefix("2026-10-0"), text)
        XCTAssertTrue(text.contains("(3 days ago)"), text)
        XCTAssertEqual(MetadataFormat.dateWithRelative(unix: 0, now: now, locale: en), "—")
        XCTAssertEqual(MetadataFormat.dateWithRelative(unix: -5, now: now, locale: en), "—")
    }
}
