import XCTest
@testable import LpxCore

final class TrackSearchRowTests: XCTestCase {
    private func summary(path: String = "/Music/Café Song.logicx", tracks: [Track]) -> ProjectSummary {
        ProjectSummary(path: path, fingerprints: [], tracks: tracks, metadata: ProjectMetadata(),
                       stats: BundleStats(sizeBytes: 0, createdAt: 0, modifiedAt: 0), projectDataMTime: 1, projectDataSize: 1)
    }

    func testRowCarriesDisplayFieldsAndFoldedSearchText() {
        let stock = AURef(typeCode: "aufx", subtype: "chan", manufacturer: "appl", offset: 0, displayName: "Channel EQ")
        let third = AURef(typeCode: "aufx", subtype: "FQ3p", manufacturer: "FabF", offset: 0)
        let t = Track(name: "Audio 7", userName: "Swéll Pad", kind: .audio, offset: 5, isActive: true, audioFx: [stock, third, stock],
                      position: 12, objectName: "Old Strings Object", isHidden: true)
        let row = TrackSearchRow.rows(for: summary(tracks: [t])).first
        XCTAssertEqual(row?.offset, 5)
        XCTAssertEqual(row?.path, "/Music/Café Song.logicx")
        XCTAssertEqual(row?.position, 12)
        XCTAssertEqual(row?.kind, .audio)
        XCTAssertEqual(row?.isHidden, true)
        XCTAssertEqual(row?.name, "Swéll Pad")
        XCTAssertEqual(row?.objectName, "Old Strings Object")
        XCTAssertEqual(row?.channel, "Audio 7")
        for needle in ["swell pad", "old strings object", "audio 7"] { XCTAssertTrue(row?.text.contains(needle) ?? false, needle) }
        XCTAssertFalse(row?.text.contains("channel eq") ?? true, "plug-in names live in their own field")
        XCTAssertEqual(row?.pluginText, "channel eq")
        XCTAssertFalse(row?.text.contains("fq3p") ?? true, "plug-ins the file doesn't name are found through the registry, not the text")
        XCTAssertEqual(row?.fingerprints, "|aufx/chan/appl|aufx/FQ3p/FabF|", "unique, in first-seen order")
        XCTAssertEqual(row?.projectText, "cafe song")
    }

    func testChannelStripsWithoutANumberAreIndexedButRoutingStripsAreNot() {
        let audio = Track(name: "Audio 1", userName: "Lead Vox", kind: .audio, offset: 11, isActive: true)   // fallback view: no number
        let aux = Track(name: "Aux 1", kind: .aux, offset: 12, isActive: true)
        let master = Track(name: "Stereo Out", kind: .output, offset: 13, isActive: true)
        let rows = TrackSearchRow.rows(for: summary(tracks: [audio, aux, master]))
        XCTAssertEqual(rows.map(\.name), ["Lead Vox"])
        XCTAssertNil(rows.first?.position)
        XCTAssertEqual(rows.first?.offset, 11)
    }

    func testDefaultNamedTrackUsesItsChannelAsDisplayName() {
        let t = Track(name: "Inst 3", kind: .instrument, offset: 1, isActive: true, position: 2)
        XCTAssertEqual(TrackSearchRow.rows(for: summary(tracks: [t])).first?.name, "Inst 3")
    }

    func testQueryFromTextFoldsAndResolvesPluginNames() {
        let q = TrackSearchQuery(text: "  SWÉLL  pro-q ") { $0 == "pro-q" ? ["aufx/FQ3p/FabF"] : [] }
        XCTAssertEqual(q.terms, ["swell", "pro-q"])
        XCTAssertEqual(q.pluginFingerprints, [[], ["aufx/FQ3p/FabF"]])
        XCTAssertTrue(TrackSearchQuery(text: "   ").isEmpty)
    }
}

final class TrackSearchDatabaseTests: XCTestCase {
    private func dbURL() throws -> URL { try Fixture.tempDir().appendingPathComponent("library.sqlite") }

    private func track(_ pos: Int, _ name: String, object: String? = nil, channel: String = "Audio 1", kind: TrackKind = .audio,
                       hidden: Bool = false, fx: [AURef] = []) -> Track {
        Track(name: channel, userName: name, kind: kind, offset: pos, isActive: true, audioFx: fx, position: pos, objectName: object ?? name, isHidden: hidden)
    }

    private func project(_ path: String, _ tracks: [Track]) -> ProjectSummary {
        ProjectSummary(path: path, fingerprints: [], tracks: tracks, metadata: ProjectMetadata(),
                       stats: BundleStats(sizeBytes: 0, createdAt: 0, modifiedAt: 0), projectDataMTime: 1, projectDataSize: 1)
    }

    private func search(_ db: SummaryDatabase, _ text: String, limit: Int = 100, fps: @escaping (String) -> [String] = { _ in [] }) async throws -> TrackSearchResult {
        try await db.searchTracks(TrackSearchQuery(text: text, fingerprints: fps), limit: limit)
    }

    private func library() async throws -> SummaryDatabase {
        let db = try SummaryDatabase(url: try dbURL())
        try await db.upsert([
            project("/m/Summer Anthem.logicx", [track(1, "Kick"), track(2, "Swell Strings", object: "Strings Object", channel: "Inst 3", kind: .instrument),
                                                track(3, "Lead Vox", hidden: true)]),
            project("/m/Winter Mix.logicx", [track(1, "Kick"), track(2, "Vocal swell up", object: "Vox Object"), track(3, "Café Pad")]),
        ])
        return db
    }

    func testPartialCaseInsensitiveMatchOnTrackNameAcrossProjects() async throws {
        let r = try await search(try await library(), "SWELL")
        XCTAssertEqual(r.hits.map { "\($0.path.split(separator: "/").last!)#\($0.position ?? 0)" }, ["Summer Anthem.logicx#2", "Winter Mix.logicx#2"])
        XCTAssertEqual(r.total, 2)
        let hit = try XCTUnwrap(r.hits.first)
        XCTAssertEqual(hit.name, "Swell Strings"); XCTAssertEqual(hit.objectName, "Strings Object")
        XCTAssertEqual(hit.channel, "Inst 3"); XCTAssertEqual(hit.kind, .instrument); XCTAssertFalse(hit.isHidden)
    }

    func testObjectNameAndChannelAreSearchable() async throws {
        let db = try await library()
        let byObject = try await search(db, "vox object")
        XCTAssertEqual(byObject.hits.map(\.name), ["Vocal swell up"])
        let byChannel = try await search(db, "inst 3")
        XCTAssertEqual(byChannel.hits.map(\.name), ["Swell Strings"])
    }

    func testAllTermsMustMatchTheSameTrack() async throws {
        let db = try await library()
        let both = try await search(db, "swell strings")
        XCTAssertEqual(both.hits.map(\.name), ["Swell Strings"])
        let none = try await search(db, "swell kick")
        XCTAssertTrue(none.hits.isEmpty)
    }

    func testFoldedMatchingIgnoresCaseAndAccents() async throws {
        let r = try await search(try await library(), "CAFE")
        XCTAssertEqual(r.hits.map(\.name), ["Café Pad"])
    }

    func testHiddenTracksAreFoundAndFlagged() async throws {
        let r = try await search(try await library(), "lead")
        XCTAssertEqual(r.hits.map(\.isHidden), [true])
    }

    func testProjectNameAloneDoesNotListEveryTrackButHelpsNarrow() async throws {
        let db = try await library()
        let onlyProject = try await search(db, "summer")
        XCTAssertTrue(onlyProject.hits.isEmpty, "a project-name match is a project result, not 3 track rows")
        let narrowed = try await search(db, "summer kick")
        XCTAssertEqual(narrowed.hits.map { $0.path.split(separator: "/").last! }, ["Summer Anthem.logicx"])
        XCTAssertEqual(narrowed.hits.map(\.name), ["Kick"])
    }

    func testPluginsAreFoundByNameThroughTheRegistryFingerprints() async throws {
        let db = try SummaryDatabase(url: try dbURL())
        let eq = AURef(typeCode: "aufx", subtype: "FQ3p", manufacturer: "FabF", offset: 0)
        try await db.upsert([project("/m/P.logicx", [track(1, "Guitar", fx: [eq]), track(2, "Bass")])])
        let r = try await search(db, "pro-q") { $0 == "pro-q" ? ["aufx/FQ3p/FabF"] : [] }
        XCTAssertEqual(r.hits.map(\.name), ["Guitar"])
        XCTAssertEqual(r.hits.first?.pluginFingerprints, ["aufx/FQ3p/FabF"])
    }

    func testPluginsNamedByTheFileAreFoundInTheText() async throws {
        let db = try SummaryDatabase(url: try dbURL())
        let stock = AURef(typeCode: "aufx", subtype: "chan", manufacturer: "appl", offset: 0, displayName: "Channel EQ")
        try await db.upsert([project("/m/P.logicx", [track(1, "Guitar", fx: [stock]), track(2, "Bass")])])
        let r = try await search(db, "channel eq")
        XCTAssertEqual(r.hits.map(\.name), ["Guitar"])
    }

    func testWildcardCharactersAreLiteral() async throws {
        let db = try SummaryDatabase(url: try dbURL())
        try await db.upsert([project("/m/P.logicx", [track(1, "100% wet"), track(2, "under_score"), track(3, "plain"), track(4, "it's \"quoted\"")])])
        let percent = try await search(db, "%"), under = try await search(db, "_"), quote = try await search(db, "'s")
        XCTAssertEqual(percent.hits.map(\.name), ["100% wet"])
        XCTAssertEqual(under.hits.map(\.name), ["under_score"])
        XCTAssertEqual(quote.hits.map(\.name), ["it's \"quoted\""])
    }

    func testReparsingReplacesTheRowsAndRemovalDeletesThem() async throws {
        let db = try await library()
        try await db.upsert([project("/m/Summer Anthem.logicx", [track(1, "Kick"), track(2, "Renamed Strings")])])
        let old = try await search(db, "swell")
        XCTAssertEqual(old.hits.map { $0.path.split(separator: "/").last! }, ["Winter Mix.logicx"])
        let renamed = try await search(db, "renamed")
        XCTAssertEqual(renamed.hits.count, 1)
        try await db.remove(paths: ["/m/Winter Mix.logicx"])
        let after = try await search(db, "swell")
        XCTAssertTrue(after.hits.isEmpty)
    }

    func testLimitCutsTheListButTotalCountsEverything() async throws {
        let db = try SummaryDatabase(url: try dbURL())
        try await db.upsert([project("/m/P.logicx", (1...30).map { track($0, "Pad \($0)") })])
        let r = try await search(db, "pad", limit: 10)
        XCTAssertEqual(r.hits.count, 10)
        XCTAssertEqual(r.total, 30)
    }

    func testResultsAreOrderedByProjectNameNaturallyThenPosition() async throws {
        let db = try SummaryDatabase(url: try dbURL())
        try await db.upsert([project("/m/Song 10.logicx", [track(2, "Pad B"), track(1, "Pad A")]), project("/m/Song 2.logicx", [track(1, "Pad C")])])
        let r = try await search(db, "pad")
        XCTAssertEqual(r.hits.map(\.name), ["Pad C", "Pad A", "Pad B"])
    }

    func testEmptyQueryFindsNothing() async throws {
        let r = try await search(try await library(), "   ")
        XCTAssertTrue(r.hits.isEmpty); XCTAssertEqual(r.total, 0)
    }

    // MARK: field filters

    private func filterLibrary() async throws -> SummaryDatabase {
        let db = try SummaryDatabase(url: try dbURL())
        let stock = AURef(typeCode: "aufx", subtype: "chan", manufacturer: "appl", offset: 0, displayName: "Channel EQ")
        let proq = AURef(typeCode: "aufx", subtype: "FQ3p", manufacturer: "FabF", offset: 0)
        try await db.upsert([
            project("/m/Summer Anthem.logicx", [track(1, "Kick", fx: [stock]), track(2, "Swell Strings", object: "Strings Object", channel: "Inst 3", kind: .instrument, fx: [proq]),
                                                track(3, "Lead Vox", hidden: true)]),
            project("/m/Winter Mix.logicx", [track(1, "Kick"), track(2, "Vocal swell up"), track(3, "Swell Pad", channel: "Inst 1", kind: .instrument)]),
        ])
        return db
    }

    private func names(_ r: TrackSearchResult) -> [String] { r.hits.map { "\($0.path.split(separator: "/").last!.prefix(6)):\($0.name)" } }

    func testKindFilterNarrowsFreeTerms() async throws {
        let db = try await filterLibrary()
        var q = TrackSearchQuery(terms: ["swell"]); q.kinds = [.instrument]
        let inst = try await db.searchTracks(q, limit: 50)
        XCTAssertEqual(names(inst), ["Summer:Swell Strings", "Winter:Swell Pad"])
        q.kinds = [.audio]
        let audio = try await db.searchTracks(q, limit: 50)
        XCTAssertEqual(names(audio), ["Winter:Vocal swell up"])
    }

    func testKindAloneListsThoseTracks() async throws {
        let db = try await filterLibrary()
        var q = TrackSearchQuery(terms: []); q.kinds = [.instrument]
        let r = try await db.searchTracks(q, limit: 50)
        XCTAssertEqual(r.total, 2)
    }

    func testNameTermsOnlyLookAtTrackObjectAndChannelNames() async throws {
        let db = try await filterLibrary()
        var q = TrackSearchQuery(terms: []); q.nameTerms = ["channel"]
        let none = try await db.searchTracks(q, limit: 50)
        XCTAssertTrue(none.hits.isEmpty, "a plug-in called Channel EQ is not a track name")
        q.nameTerms = ["strings"]
        let some = try await db.searchTracks(q, limit: 50)
        XCTAssertEqual(names(some), ["Summer:Swell Strings"])
        let free = try await db.searchTracks(TrackSearchQuery(terms: ["channel"]), limit: 50)
        XCTAssertEqual(names(free), ["Summer:Kick"], "free terms still find stock plug-in names")
    }

    func testProjectTermsNarrowButDoNotListTracksAlone() async throws {
        let db = try await filterLibrary()
        var q = TrackSearchQuery(terms: []); q.projectTerms = ["winter"]
        let alone = try await db.searchTracks(q, limit: 50)
        XCTAssertTrue(alone.hits.isEmpty)
        q.nameTerms = ["kick"]
        let both = try await db.searchTracks(q, limit: 50)
        XCTAssertEqual(names(both), ["Winter:Kick"])
    }

    func testPluginTermsMatchStockNamesAndRegistryFingerprints() async throws {
        let db = try await filterLibrary()
        var q = TrackSearchQuery(terms: []); q.pluginTerms = ["channel eq"]; q.pluginTermFingerprints = [[]]
        let stock = try await db.searchTracks(q, limit: 50)
        XCTAssertEqual(names(stock), ["Summer:Kick"])
        q.pluginTerms = ["pro-q"]; q.pluginTermFingerprints = [["aufx/FQ3p/FabF"]]
        let reg = try await db.searchTracks(q, limit: 50)
        XCTAssertEqual(names(reg), ["Summer:Swell Strings"])
        q.nameTerms = ["kick"]
        let none = try await db.searchTracks(q, limit: 50)
        XCTAssertTrue(none.hits.isEmpty, "name and plug-in conditions must hold for the same track")
    }

    func testHiddenVisibility() async throws {
        let db = try await filterLibrary()
        var q = TrackSearchQuery(terms: ["lead"])
        q.hidden = .exclude
        let ex = try await db.searchTracks(q, limit: 50)
        XCTAssertTrue(ex.hits.isEmpty)
        q.hidden = .only
        let only = try await db.searchTracks(q, limit: 50)
        XCTAssertEqual(names(only), ["Summer:Lead Vox"])
    }

    func testIndexedProjectCountCountsProjectsWithTrackRows() async throws {
        let db = try SummaryDatabase(url: try dbURL())
        try await db.upsert([project("/m/A.logicx", [track(1, "x"), track(2, "y")]), project("/m/B.logicx", [track(1, "z")]), project("/m/Empty.logicx", [])])
        let n = try await db.trackIndexedProjectCount()
        XCTAssertEqual(n, 2)
    }

    func testUnnumberedTracksAreSearchableAndSortAfterNumberedOnes() async throws {
        let db = try SummaryDatabase(url: try dbURL())
        let unnumbered = Track(name: "Audio 4", userName: "Pad Strip", kind: .audio, offset: 40, isActive: true)
        try await db.upsert([project("/m/P.logicx", [unnumbered, track(2, "Pad Numbered")])])
        let r = try await search(db, "pad")
        XCTAssertEqual(r.hits.map(\.name), ["Pad Numbered", "Pad Strip"])
        XCTAssertEqual(r.hits.map(\.position), [2, nil])
        XCTAssertEqual(r.hits.last?.offset, 40)
    }
}

final class ProjectSearchTests: XCTestCase {
    private func entry() -> ProjectListEntry {
        let t = Track(name: "Audio 1", userName: "Cymbal Swell", kind: .audio, offset: 1, isActive: true, objectName: "Crash Object")
        let s = ProjectSummary(path: "/m/Winter Mix.logicx", fingerprints: [], tracks: [t], metadata: ProjectMetadata(),
                               stats: BundleStats(sizeBytes: 0, createdAt: 0, modifiedAt: 0), projectDataMTime: 1, projectDataSize: 1)
        return ProjectListEntry(summary: s)
    }
    private func hit(_ q: ProjectSearch.Query, plugins: String = "fabfilter pro-q 3\nchannel eq") -> Bool {
        ProjectSearch.matches(q, entry: entry(), projectName: "winter mix", pluginText: plugins)
    }

    func testFreeTermsMatchProjectTrackObjectAndPluginNames() {
        XCTAssertTrue(hit(.init(terms: ["winter"])))
        XCTAssertTrue(hit(.init(terms: ["cymbal"])))
        XCTAssertTrue(hit(.init(terms: ["crash"])))
        XCTAssertTrue(hit(.init(terms: ["pro-q"])))
        XCTAssertFalse(hit(.init(terms: ["trumpet"])))
    }

    func testEveryFreeTermMustMatchSomewhere() {
        XCTAssertTrue(hit(.init(terms: ["winter", "swell", "pro-q"])))
        XCTAssertFalse(hit(.init(terms: ["winter", "trumpet"])))
    }

    func testFieldFiltersLookInTheirOwnField() {
        XCTAssertTrue(hit(.init(projectTerms: ["winter"])))
        XCTAssertFalse(hit(.init(projectTerms: ["cymbal"])))
        XCTAssertTrue(hit(.init(nameTerms: ["cymbal"])))
        XCTAssertTrue(hit(.init(pluginTerms: ["pro-q"])))
        XCTAssertFalse(hit(.init(pluginTerms: ["cymbal"])))
        XCTAssertTrue(hit(.init(terms: ["swell"], projectTerms: ["winter"], pluginTerms: ["channel"])))
        XCTAssertFalse(hit(.init(projectTerms: ["winter"], pluginTerms: ["trumpet"])))
    }

    func testTrackRestrictionsExcludeProjects() {
        XCTAssertFalse(hit(.init(terms: ["winter"], restrictsTracks: true)))
    }

    func testEmptyQueryMatchesNothing() {
        XCTAssertFalse(hit(.init()))
    }
}

final class SearchResultsTests: XCTestCase {
    private func hit(_ path: String, _ pos: Int, _ name: String) -> TrackHit {
        TrackHit(path: path, position: pos, offset: pos * 10, kind: .audio, isHidden: false, name: name, objectName: "", channel: "", pluginFingerprints: [])
    }
    private func name(_ p: String) -> String { URL(fileURLWithPath: p).deletingPathExtension().lastPathComponent }

    func testTracksAreGroupedUnderTheirProjectInGivenOrder() {
        let r = SearchResults.combine(hits: [hit("/m/B.logicx", 2, "b2"), hit("/m/A.logicx", 1, "a1"), hit("/m/B.logicx", 5, "b5")], projects: [], name: name)
        XCTAssertEqual(r.map(\.path), ["/m/A.logicx", "/m/B.logicx"])
        XCTAssertEqual(r.map { $0.tracks.map(\.name) }, [["a1"], ["b2", "b5"]])
    }

    func testWholeProjectMatchesAreMergedWithoutDuplicates() {
        let r = SearchResults.combine(hits: [hit("/m/B.logicx", 2, "b2")], projects: ["/m/C.logicx", "/m/B.logicx", "/m/C.logicx"], name: name)
        XCTAssertEqual(r.map(\.path), ["/m/B.logicx", "/m/C.logicx"])
        XCTAssertEqual(r.map(\.tracks.count), [1, 0])
    }

    func testProjectsAreInNaturalNameOrder() {
        let r = SearchResults.combine(hits: [], projects: ["/m/Song 10.logicx", "/m/Song 2.logicx", "/x/song 1.logicx"], name: name)
        XCTAssertEqual(r.map { name($0.path) }, ["song 1", "Song 2", "Song 10"])
    }

    func testNothingInNothingOut() {
        XCTAssertTrue(SearchResults.combine(hits: [], projects: [], name: name).isEmpty)
    }
}
