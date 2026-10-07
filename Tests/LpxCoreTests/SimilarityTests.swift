import XCTest
@testable import LpxCore

final class SimilarityTests: XCTestCase {
    private func meta(key: String = "C", gender: String = "major", bpm: Double = 90) -> ProjectMetadata {
        var m = ProjectMetadata(); m.songKey = key; m.songGender = gender; m.bpm = bpm; return m
    }

    // MARK: key

    func testKeyMatchesWhenKeyAndGenderEqual() {
        XCTAssertTrue(SimilarityAxis.key(songKey: "C", songGender: "major").matches(meta()))
    }

    func testKeyRejectsDifferentKeyOrGender() {
        XCTAssertFalse(SimilarityAxis.key(songKey: "D", songGender: "major").matches(meta()))
        XCTAssertFalse(SimilarityAxis.key(songKey: "C", songGender: "minor").matches(meta()))
    }

    func testKeyNeverMatchesUnknown() {
        XCTAssertFalse(SimilarityAxis.key(songKey: "C", songGender: "major").matches(meta(key: "?", gender: "?")))
        XCTAssertFalse(SimilarityAxis.key(songKey: "C", songGender: "major").matches(meta(key: "C", gender: "?")))
        XCTAssertFalse(SimilarityAxis.key(songKey: "?", songGender: "?").matches(meta(key: "?", gender: "?")))
    }

    // MARK: bpm — target rounds to nearest 5, window ±2 (90 → 88…92)

    func testBPMBandEdges() {
        let axis = SimilarityAxis.bpm(90)
        XCTAssertTrue(axis.matches(meta(bpm: 88)))
        XCTAssertTrue(axis.matches(meta(bpm: 92)))
        XCTAssertFalse(axis.matches(meta(bpm: 87)))
        XCTAssertFalse(axis.matches(meta(bpm: 93)))
    }

    func testBPMBandFollowsRoundedBucket() {
        // 93 rounds to 95 → window 93…97
        let axis = SimilarityAxis.bpm(93)
        XCTAssertTrue(axis.matches(meta(bpm: 97)))
        XCTAssertTrue(axis.matches(meta(bpm: 93)))
        XCTAssertFalse(axis.matches(meta(bpm: 92)))
        XCTAssertFalse(axis.matches(meta(bpm: 98)))
    }

    func testBPMUnknownNeverMatches() {
        XCTAssertFalse(SimilarityAxis.bpm(90).matches(meta(bpm: 0)))
        XCTAssertFalse(SimilarityAxis.bpm(0).matches(meta(bpm: 90)))
    }

    // MARK: combined

    func testKeyAndBPMNeedsBoth() {
        let axis = SimilarityAxis.keyAndBPM(songKey: "C", songGender: "major", bpm: 90)
        XCTAssertTrue(axis.matches(meta()))
        XCTAssertFalse(axis.matches(meta(bpm: 100)))
        XCTAssertFalse(axis.matches(meta(key: "D")))
        XCTAssertFalse(axis.matches(meta(key: "?", gender: "?")))
    }

    // MARK: labels

    func testLabels() {
        XCTAssertEqual(SimilarityAxis.key(songKey: "C", songGender: "major").label, "C major")
        XCTAssertEqual(SimilarityAxis.key(songKey: "F#", songGender: "Minor").label, "F# minor")
        XCTAssertEqual(SimilarityAxis.bpm(90).label, "around 90 BPM (88–92)")
        XCTAssertEqual(SimilarityAxis.bpm(92).label, "around 92 BPM (88–92)")
        XCTAssertEqual(SimilarityAxis.keyAndBPM(songKey: "C", songGender: "major", bpm: 92).label, "C major around 92 BPM (88–92)")
    }

    // MARK: axes offered for a project

    func testAxesFromProjectMetadata() {
        let m = meta(key: "A", gender: "minor", bpm: 120)
        XCTAssertEqual(SimilarityAxis.key(of: m), .key(songKey: "A", songGender: "minor"))
        XCTAssertEqual(SimilarityAxis.bpm(of: m), .bpm(120))
        XCTAssertEqual(SimilarityAxis.keyAndBPM(of: m), .keyAndBPM(songKey: "A", songGender: "minor", bpm: 120))
    }

    func testAxesAreNilWhenValuesUnknown() {
        let unknownKey = meta(key: "?", gender: "?", bpm: 120)
        XCTAssertNil(SimilarityAxis.key(of: unknownKey))
        XCTAssertNil(SimilarityAxis.keyAndBPM(of: unknownKey))
        XCTAssertNotNil(SimilarityAxis.bpm(of: unknownKey))
        XCTAssertNil(SimilarityAxis.bpm(of: meta(bpm: 0)))
    }
}
