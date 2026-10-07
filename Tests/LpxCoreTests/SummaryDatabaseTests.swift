import XCTest
@testable import LpxCore

final class SummaryDatabaseTests: XCTestCase {
    private func dbURL() throws -> URL { try Fixture.tempDir().appendingPathComponent("sub/library.sqlite") }

    private func summary(_ path: String, bpm: Double = 100, mtime: Int64 = 10, size: UInt64 = 20, plugin: String = "EQ  ") -> ProjectSummary {
        var m = ProjectMetadata(); m.bpm = bpm
        let au = AURef(typeCode: "aufx", subtype: plugin, manufacturer: "Mfr1", offset: 5)
        let track = Track(name: "Audio 1", userName: "Lead Vox", kind: .audio, offset: 1, isActive: true, audioFx: [au])
        return ProjectSummary(path: path, fingerprints: [au], tracks: [track], metadata: m,
                              stats: BundleStats(sizeBytes: 9, createdAt: 1, modifiedAt: 2),
                              projectDataMTime: mtime, projectDataSize: size,
                              alternatives: [Alternative(index: 0, displayName: "Main", isActive: true, windowImagePath: "/x/WindowImage.jpg", lastSavedUnix: 77)],
                              lastSavedFrom: "Logic Pro 12.2 (6644)", variant: 0)
    }

    func testStartsEmptyAndCreatesParentDirectory() async throws {
        let url = try dbURL()
        let db = try SummaryDatabase(url: url)
        let n = try await db.count(), e = try await db.entries(), s = try await db.stamps()
        XCTAssertEqual(n, 0); XCTAssertTrue(e.isEmpty); XCTAssertTrue(s.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    func testUpsertThenReadEntriesStampsAndFullSummary() async throws {
        let db = try SummaryDatabase(url: try dbURL())
        let a = summary("/m/a.logicx", bpm: 90, mtime: 11, size: 21), b = summary("/m/b.logicx", bpm: 120, mtime: 12, size: 22)
        try await db.upsert([a, b])

        let entries = try await db.entries()
        XCTAssertEqual(Set(entries), Set([ProjectListEntry(summary: a), ProjectListEntry(summary: b)]))
        let stamps = try await db.stamps()
        XCTAssertEqual(stamps["/m/a.logicx"], DatabaseStamp(mtime: 11, size: 21))
        XCTAssertEqual(stamps["/m/b.logicx"], DatabaseStamp(mtime: 12, size: 22))
        let full = try await db.summary(forPath: "/m/a.logicx")
        XCTAssertEqual(full, a)
        let count = try await db.count()
        XCTAssertEqual(count, 2)
    }

    func testUpsertReplacesExistingRow() async throws {
        let db = try SummaryDatabase(url: try dbURL())
        try await db.upsert([summary("/m/a.logicx", bpm: 90, mtime: 1)])
        try await db.upsert([summary("/m/a.logicx", bpm: 140, mtime: 2)])

        let count = try await db.count()
        let entry = try await db.entries().first
        let stamp = try await db.stamps()["/m/a.logicx"]
        let full = try await db.summary(forPath: "/m/a.logicx")
        XCTAssertEqual(count, 1)
        XCTAssertEqual(entry?.metadata.bpm, 140)
        XCTAssertEqual(stamp?.mtime, 2)
        XCTAssertEqual(full?.metadata.bpm, 140)
    }

    func testMissingPathAndEmptyUpsert() async throws {
        let db = try SummaryDatabase(url: try dbURL())
        try await db.upsert([])
        let missing = try await db.summary(forPath: "/nope.logicx")
        let count = try await db.count()
        XCTAssertNil(missing); XCTAssertEqual(count, 0)
    }

    func testRemove() async throws {
        let db = try SummaryDatabase(url: try dbURL())
        try await db.upsert([summary("/m/a.logicx"), summary("/m/b.logicx"), summary("/m/c.logicx")])
        try await db.remove(paths: ["/m/a.logicx", "/m/c.logicx", "/never/there.logicx"])
        let paths = try await db.entries().map(\.path)
        XCTAssertEqual(paths, ["/m/b.logicx"])
    }

    func testDataSurvivesReopening() async throws {
        let url = try dbURL()
        let a = summary("/m/a.logicx", bpm: 77)
        do { let db = try SummaryDatabase(url: url); try await db.upsert([a]) }
        let reopened = try SummaryDatabase(url: url)
        let full = try await reopened.summary(forPath: "/m/a.logicx")
        XCTAssertEqual(full, a)
    }

    /// Paths are user data: quotes, unicode, emoji, long names must round-trip and never be interpreted as SQL.
    func testAwkwardPathsRoundTripAndAreNotInterpretedAsSQL() async throws {
        let db = try SummaryDatabase(url: try dbURL())
        let paths = ["/m/it's a \"song\"; DROP TABLE projects;--.logicx", "/m/Café ☕️ 日本語.logicx", "/m/" + String(repeating: "long ", count: 200) + ".logicx", "/m/back\\slash %s %d.logicx"]
        try await db.upsert(paths.map { summary($0) })

        let stored = Set(try await db.entries().map(\.path))
        XCTAssertEqual(stored, Set(paths))
        for p in paths {
            let found = try await db.summary(forPath: p)
            XCTAssertEqual(found?.path, p)
        }
    }

    func testParserVersionChangeDiscardsOldRows() async throws {
        let url = try dbURL()
        do { let old = try SummaryDatabase(url: url, parserVersion: 1); try await old.upsert([summary("/m/a.logicx")]) }
        let newer = try SummaryDatabase(url: url, parserVersion: 2)
        let count = try await newer.count()
        XCTAssertEqual(count, 0)
        try await newer.upsert([summary("/m/b.logicx")])
        let sameVersion = try SummaryDatabase(url: url, parserVersion: 2)
        let kept = try await sameVersion.count()
        XCTAssertEqual(kept, 1)
    }

    func testCorruptFileIsReplacedNotFatal() async throws {
        let url = try dbURL()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("this is not a sqlite database".utf8).write(to: url)

        let db = try SummaryDatabase(url: url)
        try await db.upsert([summary("/m/a.logicx")])
        let count = try await db.count()
        XCTAssertEqual(count, 1)
    }

    func testConcurrentWritersDoNotLoseRows() async throws {
        let db = try SummaryDatabase(url: try dbURL())
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<20 {
                group.addTask { try? await db.upsert((0..<10).map { self.summary("/m/\(i)-\($0).logicx") }) }
            }
        }
        let count = try await db.count()
        XCTAssertEqual(count, 200)
    }

    func testGarbledRowsAreSkippedNotFatal() async throws {
        // A row whose payload no longer decodes (e.g. written by a different build) must not break the launch.
        let url = try dbURL()
        let db = try SummaryDatabase(url: url)
        try await db.upsert([summary("/m/good.logicx")])
        try await db.corruptEntryForTesting(path: "/m/bad.logicx")
        let entries = try await db.entries()
        XCTAssertEqual(entries.map(\.path), ["/m/good.logicx"])
    }
}

final class LegacyCacheCleanupTests: XCTestCase {
    func testRemovesOnlyTheObsoleteJSONCache() throws {
        let dir = try Fixture.tempDir()
        let old = dir.appendingPathComponent("parse-cache.json")
        let keep = dir.appendingPathComponent("au-registry.json")
        let db = dir.appendingPathComponent("library.sqlite")
        for f in [old, keep, db] { try Data("x".utf8).write(to: f) }

        SummaryDatabase.removeLegacyJSONCache(in: dir)

        XCTAssertFalse(FileManager.default.fileExists(atPath: old.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: keep.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: db.path))
    }

    func testMissingFileOrDirectoryIsFine() {
        SummaryDatabase.removeLegacyJSONCache(in: URL(fileURLWithPath: "/no/such/lpx-dir"))
    }
}
