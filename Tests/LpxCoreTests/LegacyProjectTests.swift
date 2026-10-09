import XCTest
@testable import LpxCore

/// Logic 4–9 projects are single `.lso` files. They're listed by name (and found by bounce, search, Reveal in Finder) but
/// their contents are not read.
final class LegacyProjectTests: XCTestCase {
    private func lso(in dir: URL, _ name: String = "Spacey.lso", bytes: Int = 2048) throws -> URL {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(name)
        try Data([0xab, 0xc0, 0x47, 0x13] + [UInt8](repeating: 7, count: bytes - 4)).write(to: url)
        return url
    }

    // MARK: discovery

    func testDiscoveryListsLsoFilesNextToBundles() throws {
        let dir = try Fixture.tempDir()
        try Fixture.logicx(in: dir, name: "Modern.logicx")
        try lso(in: dir, "Old Song.lso")
        try lso(in: dir.appendingPathComponent("Archive 2005"), "Deep.LSO")
        try Data("x".utf8).write(to: dir.appendingPathComponent("notes.txt"))
        try Data("x".utf8).write(to: dir.appendingPathComponent("song.lso.bak"))
        let found = try LogicxDiscovery.discover(in: dir).map(\.lastPathComponent).sorted()
        XCTAssertEqual(found, ["Deep.LSO", "Modern.logicx", "Old Song.lso"])
    }

    func testADirectoryCalledLsoIsNotAProjectFile() throws {
        let dir = try Fixture.tempDir()
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("folder.lso"), withIntermediateDirectories: true)
        XCTAssertTrue(try LogicxDiscovery.discover(in: dir).isEmpty)
    }

    // MARK: naming

    func testTheProjectNameDropsTheLsoExtension() {
        XCTAssertEqual(ProjectBundle.bundleName(URL(fileURLWithPath: "/m/Spacey.lso")), "Spacey")
        XCTAssertEqual(ProjectBundle.bundleName(URL(fileURLWithPath: "/m/Spacey.LSO")), "Spacey")
        XCTAssertEqual(ProjectBundle.bundleName(URL(fileURLWithPath: "/m/Song v1.logicx")), "Song v1")
    }

    // MARK: summary

    func testParsingAnLsoGivesFileFactsOnly() throws {
        let dir = try Fixture.tempDir()
        let url = try lso(in: dir, "Spacey.lso", bytes: 4096)
        let s = try ProjectParser.parse(bundle: url)
        XCTAssertEqual(s.path, url.path)
        XCTAssertEqual(s.legacyFormat, "lso")
        XCTAssertEqual(s.stats.sizeBytes, 4096)
        XCTAssertGreaterThan(s.stats.modifiedAt, 0)
        XCTAssertEqual(s.projectDataSize, 4096)
        XCTAssertGreaterThan(s.projectDataMTime, 0)
        XCTAssertTrue(s.tracks.isEmpty); XCTAssertTrue(s.fingerprints.isEmpty); XCTAssertTrue(s.alternatives.isEmpty)
        XCTAssertEqual(s.metadata.bpm, 0)
    }

    func testTheStampIsTheFilesModificationTimeAndSize() throws {
        let dir = try Fixture.tempDir()
        let url = try lso(in: dir, bytes: 3000)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1_119_000_000)], ofItemAtPath: url.path)
        let stat = ProjectParser.projectDataStat(bundle: url)
        XCTAssertEqual(stat?.mtime, 1_119_000_000)
        XCTAssertEqual(stat?.size, 3000)
    }

    func testReadingAnLsoNeverChangesIt() throws {
        let dir = try Fixture.tempDir()
        let url = try lso(in: dir)
        let before = try Data(contentsOf: url), mtime = try FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date
        _ = try ProjectParser.parse(bundle: url)
        XCTAssertEqual(try Data(contentsOf: url), before)
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date, mtime)
    }

    func testTheListEntryKnowsItIsLegacy() throws {
        let dir = try Fixture.tempDir()
        let entry = ProjectListEntry(summary: try ProjectParser.parse(bundle: try lso(in: dir, "Walk alone.lso")))
        XCTAssertTrue(entry.isLegacy)
        XCTAssertTrue(entry.searchText.contains("walk alone"), "found by name")
        XCTAssertEqual(entry.visibleTrackCount, 0)
        XCTAssertFalse(ProjectListEntry(summary: try ProjectParser.parse(bundle: try Fixture.logicx(in: dir, name: "Modern.logicx"))).isLegacy)
    }

    func testEntriesCachedBeforeLegacySupportStillDecode() throws {
        let dir = try Fixture.tempDir()
        let entry = ProjectListEntry(summary: try ProjectParser.parse(bundle: try Fixture.logicx(in: dir, name: "Modern.logicx")))
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(entry)) as! [String: Any]
        json["legacyFormat"] = nil                                  // what an old cache row looks like
        let decoded = try JSONDecoder().decode(ProjectListEntry.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(decoded, entry)
        XCTAssertFalse(decoded.isLegacy)
    }

    // MARK: scanning

    func testAMixedFolderScansBothKindsAndSkipsUnchangedOnes() async throws {
        let dir = try Fixture.tempDir()
        let modern = try Fixture.logicx(in: dir, name: "Modern.logicx"), old = try lso(in: dir, "Old.lso")
        final class Box: @unchecked Sendable { let l = NSLock(); var parsed: [ProjectSummary] = []; var unchanged = 0
            func add(_ o: ScanOutcome) { l.lock(); defer { l.unlock() }
                switch o { case .parsed(let s): parsed.append(s); case .unchanged: unchanged += 1; case .failed: break } } }
        let first = Box()
        await LibraryScanner.scan(bundles: try LogicxDiscovery.discover(in: dir), workers: 2, onOutcome: first.add)
        XCTAssertEqual(Set(first.parsed.map { $0.legacyFormat ?? "logicx" }), ["lso", "logicx"])

        var known: [String: DatabaseStamp] = [:]
        for s in first.parsed { known[s.path] = DatabaseStamp(mtime: s.projectDataMTime, size: s.projectDataSize) }
        let changed = await LibraryScanner.changedBundles([modern, old], known: known, workers: 2)
        XCTAssertTrue(changed.isEmpty, "stamps match, so nothing is re-read")
    }

    func testBouncesOfAnLsoAreFoundByName() throws {
        let dir = try Fixture.tempDir()
        let url = try lso(in: dir, "Spacey.lso")
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("Bounces"), withIntermediateDirectories: true)
        try Data([1, 2, 3, 4]).write(to: dir.appendingPathComponent("Bounces/Spacey MIX ALL.wav"))
        XCTAssertEqual(BounceFinder.find(project: url).map(\.fileName), ["Spacey MIX ALL.wav"])
    }
}
