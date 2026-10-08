import XCTest
@testable import LpxCore

final class BounceNamingTests: XCTestCase {
    private let project = "AQU 14m03 [260306] Please Follow me v02"

    private func match(_ file: String, _ name: String? = nil) -> BounceMatch? {
        BounceNaming.match(fileName: file, projectName: name ?? project)
    }

    func testExactNameIsTheMix() {
        XCTAssertEqual(match("AQU 14m03 [260306] Please Follow me v02.wav"), BounceMatch(kind: .mix))
    }

    func testMixAllAndTimestampsAreIgnored() {
        let suffixes = [" MIX ALL", " MIX ALL @09595923", " MIX ALL @10285803", " @09595923", " MIX ALL 01.02.03.04", " MIX ALL 01-02-03-04",
                        " MIX ALL_01_02_03_04", " 01.02.03.04", " mix all", " mix all @09595923"]
        for suffix in suffixes {
            XCTAssertEqual(match("\(project)\(suffix).wav"), BounceMatch(kind: .mix), suffix)
        }
    }

    func testMixVariantsWithABracketTagAreAlternatives() {
        XCTAssertEqual(match("\(project) MIX ALL [30 SECS ALT 1].wav"), BounceMatch(kind: .mix, isAlternative: true))
        XCTAssertEqual(match("\(project) MIX ALL @09595923 [60 SECS ALT 2].mp3"), BounceMatch(kind: .mix, isAlternative: true))
    }

    func testStemsCarryTheirNumberAndLabel() {
        XCTAssertEqual(match("\(project) STM#01 PIANO.wav"), BounceMatch(kind: .stem, stemNumber: 1, stemLabel: "PIANO"))
        XCTAssertEqual(match("\(project) STM#06 STRINGS 1.wav"), BounceMatch(kind: .stem, stemNumber: 6, stemLabel: "STRINGS 1"))
        XCTAssertEqual(match("\(project) STM#04 SYNTHS 2+3.wav"), BounceMatch(kind: .stem, stemNumber: 4, stemLabel: "SYNTHS 2+3"))
        XCTAssertEqual(match("\(project) STM#03 STRINGS .wav"), BounceMatch(kind: .stem, stemNumber: 3, stemLabel: "STRINGS"), "stray space before the extension")
        XCTAssertEqual(match("\(project) STM #02 PIANO 2.wav"), BounceMatch(kind: .stem, stemNumber: 2, stemLabel: "PIANO 2"), "a space before the #")
        XCTAssertEqual(match("\(project) STM#07.aif"), BounceMatch(kind: .stem, stemNumber: 7, stemLabel: nil), "the label is optional")
        XCTAssertEqual(match("\(project) STM#99 X.wav")?.stemNumber, 99)
        XCTAssertEqual(match("\(project) stm#02 pad @09595923.wav"), BounceMatch(kind: .stem, stemNumber: 2, stemLabel: "pad"), "a timestamp after the label is not part of it")
    }

    func testOtherProjectsAndVersionsDoNotMatch() {
        XCTAssertNil(match("AQU 14m03 [260306] Please Follow me v01 MIX ALL.wav"), "another version")
        XCTAssertNil(match("AQU 14m03 [260306] Please Follow me v03.wav"))
        XCTAssertNil(match("Something else entirely.wav"))
        XCTAssertNil(match("Please Follow me v02.wav"), "the name has to start the file name")
    }

    func testTheProjectNameMustEndAtAWordBoundary() {
        XCTAssertNil(BounceNaming.match(fileName: "Song v10 MIX ALL.wav", projectName: "Song v1"))
        XCTAssertNil(BounceNaming.match(fileName: "Song v1b.wav", projectName: "Song v1"))
        XCTAssertEqual(BounceNaming.match(fileName: "Song v1.wav", projectName: "Song v1"), BounceMatch(kind: .mix))
    }

    func testUnknownAppendicesAreNotBounces() {
        XCTAssertNil(match("\(project) DEMO.wav"))
        XCTAssertNil(match("\(project) alt mix.wav"))
        XCTAssertNil(match("\(project) STM.wav"), "no stem number")
        XCTAssertNil(match("\(project) STM#.wav"))
        XCTAssertNil(match("\(project) DELETE.wav"))
        XCTAssertNil(match("\(project) CUES.wav"))
        XCTAssertNil(match("\(project) DX-FX-MX.wav"))
        XCTAssertNil(match("\(project) MIX ALL DELETE.wav"))
    }

    func testCaseAccentsAndExtensionsDoNotMatter() {
        XCTAssertEqual(BounceNaming.match(fileName: "CAFÉ Song v1 mix all.AIFF", projectName: "Café Song v1"), BounceMatch(kind: .mix))
        XCTAssertEqual(BounceNaming.match(fileName: "Song v1 STM#03.m4a", projectName: "Song v1"), BounceMatch(kind: .stem, stemNumber: 3, stemLabel: nil))
        XCTAssertEqual(BounceNaming.match(fileName: "Song v1", projectName: "Song v1"), BounceMatch(kind: .mix), "no extension")
    }

    func testNamesContainingDotsKeepTheirDots() {
        XCTAssertEqual(BounceNaming.match(fileName: "Mix 2.0 v1 MIX ALL.wav", projectName: "Mix 2.0 v1"), BounceMatch(kind: .mix))
    }
}
