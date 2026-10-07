import XCTest
@testable import LpxCore

final class AuvalParserTests: XCTestCase {
    func testParsesCanonicalLine() throws {
        let e = try XCTUnwrap(AuvalParser.parseLine("aumu EZk2 Toon  -  EZdrummer 2"))
        XCTAssertEqual(e.type4CC, "aumu")
        XCTAssertEqual(e.subtype4CC, "EZk2")
        XCTAssertEqual(e.manufacturer4CC, "Toon")
        XCTAssertEqual(e.name, "EZdrummer 2")
        XCTAssertEqual(e.fingerprint, "aumu/EZk2/Toon")
    }

    func testPreservesTrailingSpaceInSubtype() throws {
        let e = try XCTUnwrap(AuvalParser.parseLine("aufx EB   SToy  -  EchoBoy"))
        XCTAssertEqual(e.subtype4CC, "EB  ")
        XCTAssertEqual(e.fingerprint, "aufx/EB  /SToy")
    }

    func testPreservesTrailingSpaceInManufacturer() throws {
        let e = try XCTUnwrap(AuvalParser.parseLine("aufx Phsr kHs   -  Phase Plant"))
        XCTAssertEqual(e.manufacturer4CC, "kHs ")
        XCTAssertEqual(e.fingerprint, "aufx/Phsr/kHs ")
    }

    func testStripsFilePathSuffix() throws {
        let e = try XCTUnwrap(AuvalParser.parseLine("aufx Cmpr appl  -  AUDynamicsProcessor (file:/System/Library/Frameworks/AudioUnit.framework)"))
        XCTAssertEqual(e.name, "AUDynamicsProcessor")
    }

    func testHyphenInsideNameIsKept() throws {
        XCTAssertEqual(AuvalParser.parseLine("aumu EZdr Toon  -  EZ-Drummer")?.name, "EZ-Drummer")
    }

    func testRejectsNonDataLines() {
        XCTAssertNil(AuvalParser.parseLine("AU Validation Tool"))
        XCTAssertNil(AuvalParser.parseLine(""))
        XCTAssertNil(AuvalParser.parseLine("CRSR: 31 dBFS, sample rate 44100"))
    }

    func testRejectsLineTooShortForThreeFourCCs() {
        XCTAssertNil(AuvalParser.parseLine("aumu EZk2 - foo"))
    }

    func testRejectsEmptyName() {
        XCTAssertNil(AuvalParser.parseLine("aumu EZk2 Toon  -  "))
    }

    func testFingerprintMatchesAURefByteForByte() throws {
        let e = try XCTUnwrap(AuvalParser.parseLine("aumu EZk2 Toon  -  EZdrummer 2"))
        XCTAssertEqual(e.fingerprint, AURef(typeCode: "aumu", subtype: "EZk2", manufacturer: "Toon", offset: 0).fingerprint)
    }

    func testNonASCIIInColumnAreaIsRejectedNotCrashed() {
        XCTAssertNil(AuvalParser.parseLine("aumü EZk2 Toon  -  Name"))
    }
}
