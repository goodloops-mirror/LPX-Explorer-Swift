import XCTest
@testable import LpxCore

final class ProjectListEntryTests: XCTestCase {
    private func au(_ type: String, _ sub: String, _ mfr: String, name: String? = nil, offset: Int = 0) -> AURef {
        AURef(typeCode: type, subtype: sub, manufacturer: mfr, offset: offset, displayName: name)
    }

    private func summary(path: String = "/Music/Café Song.logicx", plugins: [AURef] = [], tracks: [Track] = [], alts: [Alternative] = []) -> ProjectSummary {
        var m = ProjectMetadata(); m.bpm = 124; m.songKey = "A"; m.songGender = "minor"
        return ProjectSummary(path: path, fingerprints: plugins, tracks: tracks, metadata: m,
                              stats: BundleStats(sizeBytes: 5, createdAt: 1, modifiedAt: 2),
                              projectDataMTime: 1234, projectDataSize: 5678, alternatives: alts)
    }

    private func track(_ name: String, user: String? = nil, kind: TrackKind = .audio) -> Track {
        Track(name: name, userName: user, kind: kind, offset: 0, isActive: true)
    }

    func testCopiesPathMetadataAndFreshnessStamp() {
        let e = ProjectListEntry(summary: summary())
        XCTAssertEqual(e.path, "/Music/Café Song.logicx")
        XCTAssertEqual(e.metadata.bpm, 124)
        XCTAssertEqual(e.metadata.songKey, "A")
        XCTAssertEqual(e.projectDataMTime, 1234)
        XCTAssertEqual(e.projectDataSize, 5678)
        XCTAssertEqual(e.name, "Café Song")
    }

    func testPluginsAreUniqueByFingerprintWithInstanceCountsInFirstSeenOrder() {
        let eq = au("aufx", "EQ  ", "Mfr1", offset: 10), verb = au("aufx", "Verb", "Mfr2", offset: 20)
        let e = ProjectListEntry(summary: summary(plugins: [eq, verb, au("aufx", "EQ  ", "Mfr1", offset: 30), au("aufx", "EQ  ", "Mfr1", offset: 40)]))
        XCTAssertEqual(e.plugins.map(\.fingerprint), [eq.fingerprint, verb.fingerprint])
        XCTAssertEqual(e.plugins.map(\.instances), [3, 1])
    }

    func testKeepsFirstSeenDisplayNameEvenIfAnEarlierOccurrenceHadNone() {
        let e = ProjectListEntry(summary: summary(plugins: [au("aufx", "limi", "appl"), au("aufx", "limi", "appl", name: "Limiter")]))
        XCTAssertEqual(e.plugins.first?.ref.displayName, "Limiter")
    }

    func testVisibleTrackCountCountsOnlyUserVisibleKinds() {
        let e = ProjectListEntry(summary: summary(tracks: [track("Audio 1"), track("Inst 1", kind: .instrument), track("Folder", kind: .folder),
                                                           track("Bus 3", kind: .bus), track("Aux 1", kind: .aux)]))
        XCTAssertEqual(e.visibleTrackCount, 3)
    }

    func testEveryArrangementTrackCountsWhateverItsKind() {
        func arr(_ pos: Int, _ kind: TrackKind, hidden: Bool = false) -> Track {
            Track(name: "", userName: "T\(pos)", kind: kind, offset: pos, isActive: true, position: pos, isHidden: hidden)
        }
        let e = ProjectListEntry(summary: summary(tracks: [arr(1, .audio), arr(2, .unknown), arr(3, .folder), arr(4, .instrument, hidden: true)]))
        XCTAssertEqual(e.visibleTrackCount, 4, "hidden tracks and unknown kinds are still tracks")
    }

    func testSearchTextIncludesTrackAndObjectNames() {
        let t = Track(name: "Audio 7", userName: "Lead Vox take 2", kind: .audio, offset: 1, isActive: true, position: 3, objectName: "Shared Vox Object")
        let text = ProjectListEntry(summary: summary(tracks: [t])).searchText
        XCTAssertTrue(text.contains("lead vox take 2"))
        XCTAssertTrue(text.contains("shared vox object"))
        XCTAssertTrue(text.contains("audio 7"))
    }

    func testAlternativeCount() {
        let alts = [Alternative(index: 0, displayName: "A", isActive: true), Alternative(index: 1, displayName: "B", isActive: false)]
        XCTAssertEqual(ProjectListEntry(summary: summary(alts: alts)).alternativeCount, 2)
        XCTAssertEqual(ProjectListEntry(summary: summary()).alternativeCount, 0)
    }

    func testSearchTextIsFoldedAndCoversNameTracksChannelsAndAlternatives() {
        let tracks = [track("Audio 4", user: "Lead Vox"), track("Inst 2", user: nil, kind: .instrument)]
        let alts = [Alternative(index: 0, displayName: "Main", isActive: true), Alternative(index: 1, displayName: "Radio Édit", isActive: false)]
        let text = ProjectListEntry(summary: summary(tracks: tracks, alts: alts)).searchText
        for needle in ["cafe song", "lead vox", "audio 4", "inst 2", "radio edit"] { XCTAssertTrue(text.contains(needle), needle) }
        XCTAssertEqual(text, text.lowercased())
        XCTAssertFalse(text.contains("é"))
    }

    func testSingleAlternativeNameIsNotAddedToSearchText() {
        let alts = [Alternative(index: 0, displayName: "Only Variant Name", isActive: true)]
        XCTAssertFalse(ProjectListEntry(summary: summary(alts: alts)).searchText.contains("only variant name"))
    }

    func testCodableRoundTripAndSmallPayload() throws {
        let tracks = (0..<300).map { track("Audio \($0)", user: "Track number \($0)") }
        let e = ProjectListEntry(summary: summary(plugins: [au("aufx", "EQ  ", "Mfr1"), au("aumu", "Synt", "Mfr2")], tracks: tracks))
        let data = try JSONEncoder().encode(e)
        XCTAssertEqual(try JSONDecoder().decode(ProjectListEntry.self, from: data), e)
        XCTAssertLessThan(data.count, 20_000)
    }

    func testFoldIsPublicAndMatchesTheMatcher() {
        XCTAssertEqual(SearchMatcher.fold("Café ÉDIT"), "cafe edit")
    }
}
