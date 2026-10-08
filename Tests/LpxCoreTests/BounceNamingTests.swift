import XCTest
@testable import LpxCore

/// The rule: a file is a bounce of a project when its name starts with the project's name (version number included);
/// whatever follows is ignored. Only the stem number / label is read, to tell stems from the mix.
final class BounceNamingTests: XCTestCase {
    private let project = "AQU Cadmus v10"

    private func match(_ file: String, _ name: String? = nil) -> BounceMatch? {
        BounceNaming.match(fileName: file, projectName: name ?? project)
    }

    func testAnythingAfterTheProjectNameIsIgnored() {
        for tail in ["", " MIX ALL", " [Calm] MIX ALL", " MIX ALL @09595923", " whatever you like", " DELETE", " 01.02.03.04", "_final", "-2"] {
            XCTAssertEqual(match("\(project)\(tail).wav"), BounceMatch(kind: .mix), "tail: '\(tail)'")
        }
    }

    func testStemsAreRecognisedByTheirNumber() {
        XCTAssertEqual(match("\(project) STM#01 PIANO.wav"), BounceMatch(kind: .stem, stemNumber: 1, stemLabel: "PIANO"))
        XCTAssertEqual(match("\(project) [Calm] STM#12 STRINGS 1.wav"), BounceMatch(kind: .stem, stemNumber: 12, stemLabel: "STRINGS 1"))
        XCTAssertEqual(match("\(project) STM #02 PIANO 2.wav"), BounceMatch(kind: .stem, stemNumber: 2, stemLabel: "PIANO 2"))
        XCTAssertEqual(match("\(project) stm#07.aif"), BounceMatch(kind: .stem, stemNumber: 7, stemLabel: nil))
        XCTAssertEqual(match("\(project) STM#99 X.wav")?.stemNumber, 99)
    }

    func testAnotherNameDoesNotMatch() {
        XCTAssertNil(match("AQU Cadmus v09 MIX ALL.wav"), "another version")
        XCTAssertNil(match("Cadmus v10.wav"), "the name has to start the file name")
        XCTAssertNil(match("Something else entirely.wav"))
    }

    /// One small rule keeps "v1" from claiming "v10" and "v10" from claiming "v10b": the name must end where a word ends.
    func testTheNameMustEndAtTheEndOfAWord() {
        XCTAssertNil(BounceNaming.match(fileName: "Song v10 MIX ALL.wav", projectName: "Song v1"))
        XCTAssertNil(BounceNaming.match(fileName: "Song v10b MIX ALL.wav", projectName: "Song v10"))
        XCTAssertEqual(BounceNaming.match(fileName: "Song v10 MIX ALL.wav", projectName: "Song v10"), BounceMatch(kind: .mix))
        XCTAssertEqual(BounceNaming.match(fileName: "Song v10b MIX ALL.wav", projectName: "Song v10b"), BounceMatch(kind: .mix))
    }

    func testCaseAccentsAndExtensionsDoNotMatter() {
        XCTAssertEqual(BounceNaming.match(fileName: "CAFÉ Song v1 mix all.AIFF", projectName: "Café Song v1"), BounceMatch(kind: .mix))
        XCTAssertEqual(BounceNaming.match(fileName: "Song v1 STM#03.m4a", projectName: "Song v1"), BounceMatch(kind: .stem, stemNumber: 3))
        XCTAssertEqual(BounceNaming.match(fileName: "Song v1", projectName: "Song v1"), BounceMatch(kind: .mix), "no extension")
        XCTAssertEqual(BounceNaming.match(fileName: "Mix 2.0 v1 MIX ALL.wav", projectName: "Mix 2.0 v1"), BounceMatch(kind: .mix), "dots inside the name")
    }
}
