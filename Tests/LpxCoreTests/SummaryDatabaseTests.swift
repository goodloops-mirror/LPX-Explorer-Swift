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

    func testFailuresAreRememberedWithTheirStampAndClearedByAGoodParseOrRemoval() async throws {
        let db = try SummaryDatabase(url: try dbURL())
        try await db.recordFailures([ProjectFailure(path: "/m/bad.logicx", stamp: DatabaseStamp(mtime: 5, size: 6), message: "no ProjectData"),
                                     ProjectFailure(path: "/m/bad2.logicx", stamp: DatabaseStamp(mtime: 7, size: 8), message: "broken")])
        let failures = try await db.failures()
        XCTAssertEqual(failures, ["/m/bad.logicx": "no ProjectData", "/m/bad2.logicx": "broken"])
        let stamps = try await db.stamps()
        XCTAssertEqual(stamps["/m/bad.logicx"], DatabaseStamp(mtime: 5, size: 6), "so the scanner skips it until the file changes")
        let count = try await db.count()
        XCTAssertEqual(count, 0, "a failure is not a project")

        try await db.upsert([summary("/m/bad.logicx")])
        try await db.remove(paths: ["/m/bad2.logicx"])
        let after = try await db.failures()
        XCTAssertTrue(after.isEmpty)
    }

    func testStaleTracksTableIsRebuiltFromDetailsWithoutReparsing() async throws {
        let url = try dbURL()
        let db = try SummaryDatabase(url: url)
        var numbered = summary("/m/a.logicx", mtime: 3, size: 4)
        numbered.tracks[0].position = 1
        try await db.upsert([numbered])
        let fresh = try await db.rebuildTracksIfNeeded()
        XCTAssertFalse(fresh, "a table written by the current code needs no rebuild")
        try await db.invalidateTracksForTesting()

        let reopened = try SummaryDatabase(url: url)
        let before = try await reopened.searchTracks(TrackSearchQuery(terms: ["lead"]), limit: 10)
        XCTAssertTrue(before.hits.isEmpty)
        let rebuilt = try await reopened.rebuildTracksIfNeeded()
        XCTAssertTrue(rebuilt)
        let after = try await reopened.searchTracks(TrackSearchQuery(terms: ["lead"]), limit: 10)
        XCTAssertEqual(after.hits.map(\.name), ["Lead Vox"])
        let stamps = try await reopened.stamps(), count = try await reopened.count()
        XCTAssertEqual(stamps["/m/a.logicx"], DatabaseStamp(mtime: 3, size: 4), "projects are kept")
        XCTAssertEqual(count, 1)
        let again = try await reopened.rebuildTracksIfNeeded()
        XCTAssertFalse(again)
    }

    private func bounce(_ name: String, kind: BounceKind = .mix, stem: Int? = nil, size: UInt64 = 10, mtime: Int64 = 5) -> BounceFile {
        BounceFile(path: "/m/Bounces/\(name)", fileName: name, kind: kind, stemNumber: stem, sizeBytes: size, mtimeUnix: mtime)
    }

    func testBouncesAreRememberedPerProjectAndReplaced() async throws {
        let db = try SummaryDatabase(url: try dbURL())
        let mix = bounce("A MIX ALL.wav"), stem = bounce("A STM#01.wav", kind: .stem, stem: 1)
        try await db.saveBounces(["/m/A.logicx": [mix, stem], "/m/B.logicx": [bounce("B.wav")]])
        let all = try await db.bounces()
        XCTAssertEqual(all["/m/A.logicx"], [mix, stem], "order is kept")
        XCTAssertEqual(all["/m/B.logicx"]?.map(\.fileName), ["B.wav"])

        try await db.saveBounces(["/m/A.logicx": [bounce("A v2.wav")]])
        let replaced = try await db.bounces()
        XCTAssertEqual(replaced["/m/A.logicx"]?.map(\.fileName), ["A v2.wav"])
        XCTAssertNotNil(replaced["/m/B.logicx"], "other projects are untouched")

        try await db.saveBounces(["/m/A.logicx": []])
        let cleared = try await db.bounces()
        XCTAssertNil(cleared["/m/A.logicx"])
    }

    func testStemLabelsSurviveTheCache() async throws {
        let db = try SummaryDatabase(url: try dbURL())
        let stem = BounceFile(path: "/b/A STM#03 STRINGS 1.wav", fileName: "A STM#03 STRINGS 1.wav", kind: .stem, stemNumber: 3, stemLabel: "STRINGS 1",
                              sizeBytes: 5, mtimeUnix: 6)
        let mix = BounceFile(path: "/b/A [Calm] MIX ALL.wav", fileName: "A [Calm] MIX ALL.wav", kind: .mix, stemNumber: nil, stemLabel: nil, sizeBytes: 7, mtimeUnix: 8)
        try await db.saveBounces(["/m/A.logicx": [mix, stem]])
        let all = try await db.bounces()
        XCTAssertEqual(all["/m/A.logicx"], [mix, stem])
    }

    func testRemovingAProjectForgetsItsBounces() async throws {
        let db = try SummaryDatabase(url: try dbURL())
        try await db.upsert([summary("/m/A.logicx")])
        try await db.saveBounces(["/m/A.logicx": [bounce("A.wav")]])
        try await db.remove(paths: ["/m/A.logicx"])
        let after = try await db.bounces()
        XCTAssertTrue(after.isEmpty)
    }

    func testFailureIsReplacedWhenTheSameProjectFailsAgain() async throws {
        let db = try SummaryDatabase(url: try dbURL())
        try await db.recordFailures([ProjectFailure(path: "/m/x.logicx", stamp: DatabaseStamp(mtime: 1, size: 1), message: "first")])
        try await db.recordFailures([ProjectFailure(path: "/m/x.logicx", stamp: DatabaseStamp(mtime: 2, size: 2), message: "second")])
        let failures = try await db.failures(), stamps = try await db.stamps()
        XCTAssertEqual(failures, ["/m/x.logicx": "second"])
        XCTAssertEqual(stamps["/m/x.logicx"], DatabaseStamp(mtime: 2, size: 2))
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

final class FileInfoDatabaseTests: XCTestCase {
    func testFileInfoIsRememberedAndReplacedPerProject() async throws {
        let db = try SummaryDatabase(url: try Fixture.tempDir().appendingPathComponent("library.sqlite"))
        let a = ProjectFileInfo(created: 10, modified: 20, tags: ["Red", "Client X"]), b = ProjectFileInfo(created: 11, modified: 21, tags: [])
        try await db.saveFileInfo(["/m/A.logicx": a, "/m/B.logicx": b])
        let first = try await db.fileInfo()
        XCTAssertEqual(first["/m/A.logicx"], a)
        XCTAssertEqual(first["/m/B.logicx"], b)

        let a2 = ProjectFileInfo(created: 10, modified: 99, tags: ["Final"])
        try await db.saveFileInfo(["/m/A.logicx": a2])
        let second = try await db.fileInfo()
        XCTAssertEqual(second["/m/A.logicx"], a2)
        XCTAssertEqual(second["/m/B.logicx"], b, "other projects are untouched")
    }

    func testTagsWithAwkwardCharactersSurvive() async throws {
        let db = try SummaryDatabase(url: try Fixture.tempDir().appendingPathComponent("library.sqlite"))
        let info = ProjectFileInfo(created: 1, modified: 2, tags: ["Café \"Müller\"", "a,b", "with\nnewline", "日本語"])
        try await db.saveFileInfo(["/m/A.logicx": info])
        let all = try await db.fileInfo()
        XCTAssertEqual(all["/m/A.logicx"], info)
    }

    func testRemovingAProjectForgetsItsFileInfo() async throws {
        let db = try SummaryDatabase(url: try Fixture.tempDir().appendingPathComponent("library.sqlite"))
        try await db.saveFileInfo(["/m/A.logicx": ProjectFileInfo(created: 1, modified: 2, tags: ["x"])])
        try await db.remove(paths: ["/m/A.logicx"])
        let all = try await db.fileInfo()
        XCTAssertTrue(all.isEmpty)
    }
}
