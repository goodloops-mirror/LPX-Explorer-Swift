import XCTest
@testable import LpxCore

final class LibraryFilterTests: XCTestCase {
    private func summary(_ path: String, key: String = "C", gender: String = "major", bpm: Double = 120, plugins: [AURef] = []) -> ProjectSummary {
        var m = ProjectMetadata(); m.songKey = key; m.songGender = gender; m.bpm = bpm
        return ProjectSummary(path: path, fingerprints: plugins, metadata: m,
                              stats: BundleStats(sizeBytes: 0, createdAt: 0, modifiedAt: 0), projectDataMTime: 0, projectDataSize: 0)
    }

    private let installedPlugin = AURef(typeCode: "aufx", subtype: "Here", manufacturer: "Mfr1", offset: 0)
    private let missingPlugin = AURef(typeCode: "aufx", subtype: "Gone", manufacturer: "Mfr2", offset: 0)

    func testNoFilterKeepsEverythingIncludingUnreadProjects() {
        let out = LibraryFilter().apply(to: ["a", "b"], entries: ["a": summary("a")].mapValues(ProjectListEntry.init(summary:)), installed: nil)
        XCTAssertEqual(out, ["a", "b"])
        XCTAssertFalse(LibraryFilter().isActive)
    }

    func testSimilarityKeepsMatchesAndDropsUnreadProjects() {
        let s = ["a": summary("a", bpm: 120), "b": summary("b", bpm: 90), "c": summary("c", bpm: 121)]
        let out = LibraryFilter(similarity: .bpm(120)).apply(to: ["a", "b", "c", "unread"], entries: s.mapValues(ProjectListEntry.init(summary:)), installed: nil)
        XCTAssertEqual(out, ["a", "c"])
    }

    func testOnlyMissingKeepsProjectsWithAtLeastOneMissingPlugin() {
        let s = ["ok": summary("ok", plugins: [installedPlugin]),
                 "bad": summary("bad", plugins: [installedPlugin, missingPlugin]),
                 "none": summary("none")]
        let out = LibraryFilter(onlyMissingPlugins: true).apply(to: ["ok", "bad", "none"], entries: s.mapValues(ProjectListEntry.init(summary:)), installed: [installedPlugin.fingerprint])
        XCTAssertEqual(out, ["bad"])
    }

    func testOnlyMissingIsInertWhileRegistryUnknown() {
        // With no AU registry we can't tell what's missing, so nothing qualifies.
        let s = ["bad": summary("bad", plugins: [missingPlugin])]
        XCTAssertTrue(LibraryFilter(onlyMissingPlugins: true).apply(to: ["bad"], entries: s.mapValues(ProjectListEntry.init(summary:)), installed: nil).isEmpty)
    }

    func testFiltersCombine() {
        let s = ["a": summary("a", bpm: 120, plugins: [missingPlugin]),
                 "b": summary("b", bpm: 90, plugins: [missingPlugin]),
                 "c": summary("c", bpm: 120, plugins: [installedPlugin])]
        let f = LibraryFilter(similarity: .bpm(120), onlyMissingPlugins: true)
        XCTAssertEqual(f.apply(to: ["a", "b", "c"], entries: s.mapValues(ProjectListEntry.init(summary:)), installed: [installedPlugin.fingerprint]), ["a"])
        XCTAssertTrue(f.isActive)
    }

    func testPreservesInputOrder() {
        let s = ["z": summary("z"), "a": summary("a"), "m": summary("m")]
        XCTAssertEqual(LibraryFilter(similarity: .bpm(120)).apply(to: ["z", "a", "m"], entries: s.mapValues(ProjectListEntry.init(summary:)), installed: nil), ["z", "a", "m"])
    }
}
