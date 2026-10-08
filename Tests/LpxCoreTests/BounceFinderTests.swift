import XCTest
@testable import LpxCore

final class BounceFinderTests: XCTestCase {
    private func touch(_ url: URL, bytes: Int = 4, modified: Date? = nil) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 1, count: bytes).write(to: url)
        if let modified { try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path) }
    }
    private func names(_ files: [BounceFile]) -> [String] { files.map(\.fileName) }

    func testBouncesFolderNextToTheProjectIncludingSubfolders() throws {
        let dir = try Fixture.tempDir()
        let project = try Fixture.logicx(in: dir, name: "Song v1.logicx")
        try touch(dir.appendingPathComponent("Bounces/Song v1 MIX ALL 01.02.03.04.wav"), bytes: 100)
        try touch(dir.appendingPathComponent("Bounces/Stems/Song v1 STM#02.wav"))
        try touch(dir.appendingPathComponent("Bounces/Stems/Song v1 STM#01.wav"))
        try touch(dir.appendingPathComponent("Bounces/Song v2 MIX ALL.wav"))        // another version
        try touch(dir.appendingPathComponent("Bounces/Song v1 notes.txt"))           // not audio
        try touch(dir.appendingPathComponent("Song v1 MIX ALL.wav"))                 // not in a Bounces folder

        let found = BounceFinder.find(project: project)

        XCTAssertEqual(names(found), ["Song v1 MIX ALL 01.02.03.04.wav", "Song v1 STM#01.wav", "Song v1 STM#02.wav"], "mix first, then stems by number")
        XCTAssertEqual(found.map(\.kind), [.mix, .stem, .stem])
        XCTAssertEqual(found.map(\.stemNumber), [nil, 1, 2])
        XCTAssertEqual(found.first?.sizeBytes, 100)
        XCTAssertEqual(found.first?.path, dir.appendingPathComponent("Bounces/Song v1 MIX ALL 01.02.03.04.wav").path)
    }

    func testFolderProjectLayout() throws {
        let dir = try Fixture.tempDir()
        let folder = dir.appendingPathComponent("Song v1")
        let project = try Fixture.logicx(in: folder, name: "Song v1.logicx")
        try touch(folder.appendingPathComponent("Bounces/Song v1.aif"))
        XCTAssertEqual(names(BounceFinder.find(project: project)), ["Song v1.aif"])
    }

    func testBouncesInsideThePackage() throws {
        let dir = try Fixture.tempDir()
        let project = try Fixture.logicx(in: dir, name: "Song v1.logicx")
        try touch(project.appendingPathComponent("Bounces/Song v1.wav"))
        try touch(project.appendingPathComponent("Alternatives/000/Bounces/Deep/Song v1 STM#01.wav"))
        try touch(project.appendingPathComponent("Media/Bounces/Song v1 STM#02.wav"))
        XCTAssertEqual(names(BounceFinder.find(project: project)), ["Song v1.wav", "Song v1 STM#01.wav", "Song v1 STM#02.wav"])
    }

    func testNoBounceMeansEmptyAndNothingIsWritten() throws {
        let dir = try Fixture.tempDir()
        let project = try Fixture.logicx(in: dir, name: "Lonely.logicx")
        try touch(dir.appendingPathComponent("Bounces/Other.wav"))
        let before = try FileManager.default.contentsOfDirectory(atPath: dir.path).sorted()
        XCTAssertTrue(BounceFinder.find(project: project).isEmpty)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: dir.path).sorted(), before)
    }

    func testSeveralProjectsShareOneBouncesFolderAndOneListing() throws {
        let dir = try Fixture.tempDir()
        let a = try Fixture.logicx(in: dir, name: "A v1.logicx"), b = try Fixture.logicx(in: dir, name: "B v1.logicx")
        try touch(dir.appendingPathComponent("Bounces/A v1 MIX ALL.wav"))
        try touch(dir.appendingPathComponent("Bounces/B v1 MIX ALL.wav"))
        let cache = BounceListingCache()
        XCTAssertEqual(names(BounceFinder.find(project: a, cache: cache)), ["A v1 MIX ALL.wav"])
        try FileManager.default.removeItem(at: dir.appendingPathComponent("Bounces/B v1 MIX ALL.wav"))
        XCTAssertEqual(names(BounceFinder.find(project: b, cache: cache)), ["B v1 MIX ALL.wav"], "the shared folder was listed once for this pass")
        XCTAssertTrue(BounceFinder.find(project: b).isEmpty, "a fresh pass sees the deletion")
    }

    func testAMissingBouncesFolderIsFine() throws {
        let dir = try Fixture.tempDir()
        let project = try Fixture.logicx(in: dir, name: "Song.logicx")
        XCTAssertTrue(BounceFinder.find(project: project).isEmpty)
    }

    func testFilesAreSortedNewestFirstWhenSeveralMixesMatch() throws {
        let dir = try Fixture.tempDir()
        let project = try Fixture.logicx(in: dir, name: "Song v1.logicx")
        try touch(dir.appendingPathComponent("Bounces/Song v1 MIX ALL 01.00.00.00.wav"), modified: Date(timeIntervalSince1970: 1_000))
        try touch(dir.appendingPathComponent("Bounces/Song v1 MIX ALL 02.00.00.00.wav"), modified: Date(timeIntervalSince1970: 2_000))
        XCTAssertEqual(names(BounceFinder.find(project: project)), ["Song v1 MIX ALL 02.00.00.00.wav", "Song v1 MIX ALL 01.00.00.00.wav"])
    }
}
