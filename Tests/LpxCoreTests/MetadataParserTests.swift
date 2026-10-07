import XCTest
@testable import LpxCore

final class MetadataParserTests: XCTestCase {
    private func xmlPlist(_ body: String) -> Data {
        Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict>\(body)</dict></plist>
        """.utf8)
    }

    func testExtractsAllDocumentedFields() throws {
        let data = xmlPlist("""
        <key>SongKey</key><string>C</string>
        <key>SongGenderKey</key><string>major</string>
        <key>BeatsPerMinute</key><real>120.0</real>
        <key>SongSignatureNumerator</key><integer>3</integer>
        <key>SongSignatureDenominator</key><integer>8</integer>
        <key>NumberOfTracks</key><integer>7</integer>
        <key>SampleRate</key><integer>44100</integer>
        <key>AudioFiles</key><array><string>a.wav</string><string>b.wav</string></array>
        <key>ImpulsResponsesFiles</key><array><string>ir.wav</string></array>
        <key>FrameRateIndex</key><integer>2</integer>
        """)

        let m = try MetadataParser.parse(data)

        XCTAssertEqual(m.songKey, "C")
        XCTAssertEqual(m.songGender, "major")
        XCTAssertEqual(m.bpm, 120.0)
        XCTAssertEqual(m.sigNumerator, 3)
        XCTAssertEqual(m.sigDenominator, 8)
        XCTAssertEqual(m.trackCount, 7)
        XCTAssertEqual(m.sampleRate, 44100)
        XCTAssertEqual(m.audioFileCount, 2)
        XCTAssertEqual(m.impulseResponseCount, 1)
        XCTAssertEqual(m.frameRateIndex, 2)
    }

    func testMissingKeysUseDefaults() throws {
        let m = try MetadataParser.parse(xmlPlist(""))

        XCTAssertEqual(m.songKey, "?")
        XCTAssertEqual(m.songGender, "?")
        XCTAssertEqual(m.bpm, 0)
        XCTAssertEqual(m.sigNumerator, 4)
        XCTAssertEqual(m.sigDenominator, 4)
        XCTAssertEqual(m.audioFileCount, 0)
    }

    func testIntegerBpmIsAccepted() throws {
        let m = try MetadataParser.parse(xmlPlist("<key>BeatsPerMinute</key><integer>90</integer>"))
        XCTAssertEqual(m.bpm, 90)
    }

    func testGarbageThrowsInvalid() {
        XCTAssertThrowsError(try MetadataParser.parse(Data("not a plist".utf8))) { error in
            guard case MetadataError.invalid = error else { return XCTFail("wrong error \(error)") }
        }
    }
}
