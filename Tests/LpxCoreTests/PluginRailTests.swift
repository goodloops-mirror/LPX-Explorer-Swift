import XCTest
@testable import LpxCore

private extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}

final class PluginRailTests: XCTestCase {
    private func au(_ type: String, _ sub: String, _ mfr: String, name: String? = nil, offset: Int = 0) -> AURef {
        AURef(typeCode: type, subtype: sub, manufacturer: mfr, offset: offset, displayName: name)
    }

    private func summary(_ path: String, _ plugins: [AURef]) -> ProjectSummary {
        ProjectSummary(path: path, fingerprints: plugins, metadata: ProjectMetadata(),
                       stats: BundleStats(sizeBytes: 0, createdAt: 0, modifiedAt: 0), projectDataMTime: 0, projectDataSize: 0)
    }

    private func entry(_ fp: String, _ name: String) -> AuvalEntry {
        let p = fp.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        return AuvalEntry(fingerprint: fp, type4CC: p[0], subtype4CC: p[1], manufacturer4CC: p[2], name: name)
    }

    // MARK: rollup

    func testRollupCountsProjectsAndInstances() {
        let eq = au("aufx", "EQ  ", "Mfr1"), verb = au("aufx", "Verb", "Mfr2")
        let rolled = PluginRollup.aggregate([
            "/a.logicx": summary("/a.logicx", [eq, eq, verb]),
            "/b.logicx": summary("/b.logicx", [eq]),
        ].mapValues(ProjectListEntry.init(summary:)))
        let byFP = Dictionary(uniqueKeysWithValues: rolled.map { ($0.fingerprint, $0) })
        XCTAssertEqual(byFP[eq.fingerprint]?.projectCount, 2)
        XCTAssertEqual(byFP[eq.fingerprint]?.instanceCount, 3)
        XCTAssertEqual(byFP[verb.fingerprint]?.projectCount, 1)
        XCTAssertEqual(byFP[eq.fingerprint]?.projectPaths, ["/a.logicx", "/b.logicx"])
    }

    func testRollupSortsByProjectCountThenFingerprint() {
        let x = au("aufx", "XXXX", "Mfr1"), y = au("aufx", "YYYY", "Mfr1"), z = au("aufx", "ZZZZ", "Mfr1")
        let rolled = PluginRollup.aggregate([
            "/1": summary("/1", [z, y, x]), "/2": summary("/2", [z]), "/3": summary("/3", [z, y]),
        ].mapValues(ProjectListEntry.init(summary:)))
        XCTAssertEqual(rolled.map(\.fingerprint), [z.fingerprint, y.fingerprint, x.fingerprint])
    }

    func testRollupKeepsFirstSeenDisplayName() {
        let named = au("aufx", "limi", "appl", name: "Limiter")
        let rolled = PluginRollup.aggregate(["/a": summary("/a", [au("aufx", "limi", "appl")]), "/b": summary("/b", [named])].mapValues(ProjectListEntry.init(summary:)))
        XCTAssertEqual(rolled.first?.displayName, "Limiter")
    }

    func testRollupOfNothingIsEmpty() { XCTAssertTrue(PluginRollup.aggregate([:]).isEmpty) }

    // MARK: rows

    private func rolled(_ fp: AURef, projects: Int = 1, instances: Int = 1) -> RolledPlugin {
        RolledPlugin(fingerprint: fp.fingerprint, displayName: fp.displayName,
                     projectPaths: (0..<projects).map { "/p\($0)" }, instanceCount: instances)
    }

    func testRowStatusAndNameFromRegistry() {
        let installed = au("aufx", "Here", "Mfr1"), missing = au("aufx", "Gone", "Mfr2")
        let rows = PluginRail.rows([rolled(installed), rolled(missing)], registry: [installed.fingerprint: entry(installed.fingerprint, "Here Plug")])
        XCTAssertEqual(rows[safe: 0]?.name, "Here Plug"); XCTAssertEqual(rows[safe: 0]?.status, .installed); XCTAssertEqual(rows[safe: 0]?.hasRegistryEntry, true)
        XCTAssertEqual(rows[safe: 1]?.name, missing.fingerprint); XCTAssertEqual(rows[safe: 1]?.status, .missing); XCTAssertEqual(rows[safe: 1]?.hasRegistryEntry, false)
    }

    func testStatusUnknownWithoutRegistryButStockIsAlwaysInstalled() {
        let plain = au("aufx", "Here", "Mfr1"), stock = au("aufx", "chan", "appl", name: "Channel EQ")
        let rows = PluginRail.rows([rolled(plain), rolled(stock)], registry: nil)
        XCTAssertEqual(rows[safe: 0]?.status, .unknown)
        XCTAssertEqual(rows[safe: 1]?.status, .installed)
        XCTAssertEqual(rows[safe: 1]?.name, "Channel EQ")
        XCTAssertEqual(rows[safe: 1]?.fineCategory, .eq)
    }

    func testRowFineCategoryUsesRegistryNameThenTypeFallback() {
        let comp = au("aufx", "Cmpr", "Mfr1")
        let inst = au("aumu", "Synt", "Mfr1")
        let rows = PluginRail.rows([rolled(comp), rolled(inst)], registry: [comp.fingerprint: entry(comp.fingerprint, "Compressor")])
        XCTAssertEqual(rows[safe: 0]?.fineCategory, .dynamics)
        XCTAssertEqual(rows[safe: 1]?.fineCategory, .instrument)
    }

    // MARK: filter

    private func sampleRows() -> [PluginRow] {
        let eq = au("aufx", "chan", "appl", name: "Channel EQ"), lim = au("aufx", "limi", "appl", name: "Limiter")
        let gone = au("aufx", "Gone", "Mfr2"), synth = au("aumu", "Synt", "Mfr1")
        return PluginRail.rows([rolled(eq, projects: 3), rolled(lim, projects: 1), rolled(gone, projects: 2), rolled(synth, projects: 1)],
                               registry: ["aumu/Synt/Mfr1": entry("aumu/Synt/Mfr1", "Big Synth")])
    }

    func testFilterByQueryMatchesNameOrFingerprintCaseInsensitively() {
        XCTAssertEqual(PluginRail.filter(sampleRows(), query: "  BIG ", status: .all, category: nil).map(\.name), ["Big Synth"])
        XCTAssertEqual(PluginRail.filter(sampleRows(), query: "aufx/gone", status: .all, category: nil).count, 1)
        XCTAssertEqual(PluginRail.filter(sampleRows(), query: "", status: .all, category: nil).count, 4)
    }

    func testFilterByStatusChips() {
        XCTAssertEqual(PluginRail.filter(sampleRows(), query: "", status: .missing, category: nil).count, 1)
        XCTAssertEqual(PluginRail.filter(sampleRows(), query: "", status: .installed, category: nil).count, 3)
        XCTAssertEqual(PluginRail.filter(sampleRows(), query: "", status: .multipleProjects, category: nil).count, 2)
    }

    func testFilterByCategoryAndCombination() {
        XCTAssertEqual(PluginRail.filter(sampleRows(), query: "", status: .all, category: .dynamics).map(\.name), ["Limiter"])
        XCTAssertTrue(PluginRail.filter(sampleRows(), query: "limiter", status: .missing, category: nil).isEmpty)
    }

    // MARK: facets & sort

    func testFacetsSortedByCountThenNameWithUncategorisedLast() {
        let rows = PluginRail.rows([
            rolled(au("aufx", "aaaa", "appl", name: "Channel EQ")), rolled(au("aufx", "bbbb", "appl", name: "Match EQ")),
            rolled(au("aufx", "cccc", "appl", name: "Limiter")), rolled(au("aufx", "dddd", "appl", name: "Chorus")),
            rolled(au("aufx", "eeee", "Mfr1")), rolled(au("aufx", "ffff", "Mfr1")), rolled(au("aufx", "gggg", "Mfr1")),
        ], registry: nil)
        let facets = PluginRail.facets(rows)
        XCTAssertEqual(facets.map(\.category), [.eq, .dynamics, .modulation, .uncategorised])
        XCTAssertEqual(facets.map(\.count), [2, 1, 1, 3])
    }

    func testSortedByUsageThenName() {
        let a = au("aufx", "aaaa", "appl", name: "Zed"), b = au("aufx", "bbbb", "appl", name: "Alpha"), c = au("aufx", "cccc", "appl", name: "Mid")
        let rows = PluginRail.rows([rolled(a, projects: 2), rolled(b, projects: 1), rolled(c, projects: 2)], registry: nil)
        XCTAssertEqual(PluginRail.sortedByUsage(rows).map(\.name), ["Mid", "Zed", "Alpha"])
    }
}
