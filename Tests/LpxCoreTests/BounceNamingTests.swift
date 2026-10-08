import XCTest
@testable import LpxCore

final class BounceNamingTests: XCTestCase {
    private let project = "AQU 14m03 [260306] Please Follow me v02"

    private func match(_ file: String, _ name: String? = nil) -> BounceMatch? {
        BounceNaming.match(fileName: file, projectName: name ?? project)
    }

    func testExactNameIsTheMix() {
        XCTAssertEqual(match("AQU 14m03 [260306] Please Follow me v02.wav"), BounceMatch(kind: .mix, stemNumber: nil))
    }

    func testMixAllAndSMPTETimestampAreIgnored() {
        for suffix in [" MIX ALL", " MIX ALL 01.02.03.04", " MIX ALL 01-02-03-04", " MIX ALL_01_02_03_04", " MIX ALL 00.14.03.12", " 01.02.03.04", " mix all"] {
            XCTAssertEqual(match("\(project)\(suffix).wav"), BounceMatch(kind: .mix, stemNumber: nil), suffix)
        }
    }

    func testStemsCarryTheirNumber() {
        XCTAssertEqual(match("\(project) STM#01.wav"), BounceMatch(kind: .stem, stemNumber: 1))
        XCTAssertEqual(match("\(project) STM#07.aif"), BounceMatch(kind: .stem, stemNumber: 7))
        XCTAssertEqual(match("\(project) STM#15.wav"), BounceMatch(kind: .stem, stemNumber: 15))
        XCTAssertEqual(match("\(project) STM#99.wav"), BounceMatch(kind: .stem, stemNumber: 99))
        XCTAssertEqual(match("\(project) stm#02 01.02.03.04.wav"), BounceMatch(kind: .stem, stemNumber: 2), "a timestamp after the stem number is ignored too")
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
        XCTAssertEqual(BounceNaming.match(fileName: "Song v1.wav", projectName: "Song v1"), BounceMatch(kind: .mix, stemNumber: nil))
    }

    func testUnknownAppendicesAreNotBounces() {
        XCTAssertNil(match("\(project) DEMO.wav"))
        XCTAssertNil(match("\(project) alt mix.wav"))
        XCTAssertNil(match("\(project) STM.wav"), "no stem number")
        XCTAssertNil(match("\(project) STM#.wav"))
    }

    func testCaseAccentsAndExtensionsDoNotMatter() {
        XCTAssertEqual(BounceNaming.match(fileName: "CAFÉ Song v1 mix all.AIFF", projectName: "Café Song v1"), BounceMatch(kind: .mix, stemNumber: nil))
        XCTAssertEqual(BounceNaming.match(fileName: "Song v1 STM#03.m4a", projectName: "Song v1"), BounceMatch(kind: .stem, stemNumber: 3))
        XCTAssertEqual(BounceNaming.match(fileName: "Song v1", projectName: "Song v1"), BounceMatch(kind: .mix, stemNumber: nil), "no extension")
    }

    func testNamesContainingDotsKeepTheirDots() {
        XCTAssertEqual(BounceNaming.match(fileName: "Mix 2.0 v1 MIX ALL.wav", projectName: "Mix 2.0 v1"), BounceMatch(kind: .mix, stemNumber: nil))
    }
}
