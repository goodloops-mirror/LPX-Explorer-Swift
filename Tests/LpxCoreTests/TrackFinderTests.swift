import XCTest
@testable import LpxCore

final class TrackFinderTests: XCTestCase {
    /// NUL, then a 16-byte name field (0x20 + ASCII, NUL padded), then an 8-byte descriptor.
    private func strip(_ name: String, _ desc: [UInt8] = [0xAB, 0x00, 0x00, 0xC5, 0, 0, 0, 0], pad: UInt8 = 0) -> [UInt8] {
        var field = [0x20] + Array(name.utf8)
        field += [UInt8](repeating: pad, count: 16 - field.count)
        return [0x00] + field + desc
    }

    private func au(_ type: String, _ sub: String = "abcd", offset: Int) -> AURef {
        AURef(typeCode: type, subtype: sub, manufacturer: "Mfr1", offset: offset)
    }

    private func track(_ name: String, _ kind: TrackKind, offset: Int, active: Bool = true, user: String? = nil) -> Track {
        Track(name: name, userName: user, kind: kind, offset: offset, isActive: active)
    }

    // MARK: findTracks

    func testFindsAudioTrack() {
        let t = TrackFinder.findTracks(strip("Audio 1"))
        XCTAssertEqual(t.count, 1)
        XCTAssertEqual(t.first?.name, "Audio 1")
        XCTAssertEqual(t.first?.kind, .audio)
        XCTAssertEqual(t.first?.offset, 1)
        XCTAssertNil(t.first?.userName)
    }

    func testClassifiesDescriptorHeadBytes() {
        let cases: [([UInt8], TrackKind)] = [
            ([0x89, 0, 0, 0xC5, 0, 0, 0, 0], .master), ([0x49, 0, 0, 0xC5, 0, 0, 0, 0], .output),
            ([0xE9, 0, 0, 0xC5, 0, 0, 0, 0], .bus), ([0xAB, 0xF5, 0, 0xC5, 0, 0, 0, 0], .aux),
            ([0xAB, 0x00, 0, 0xC5, 0, 0, 0, 0], .audio), ([0x29, 0, 0xF3, 0xC5, 0, 0, 0, 0], .instrument),
            ([0x29, 0, 0xF7, 0xC5, 0, 0, 0, 0], .instrument), ([0x29, 0, 0x00, 0xC5, 0, 0, 0, 0], .input),
            ([0x77, 0, 0, 0xC5, 0, 0, 0, 0], .unknown),
        ]
        for (desc, kind) in cases { XCTAssertEqual(TrackFinder.findTracks(strip("T", desc)).first?.kind, kind, "\(desc)") }
    }

    func testRejectsGarbageInPaddingAndMissingHighBits() {
        XCTAssertTrue(TrackFinder.findTracks(strip("Audio 1", pad: 0xFF)).isEmpty, "non-printable padding")
        var afterNul = strip("Hi")
        afterNul[1 + 1 + 2 + 3] = 0x41 // printable byte after the terminating NUL
        XCTAssertTrue(TrackFinder.findTracks(afterNul).isEmpty, "garbage after NUL")
        XCTAssertTrue(TrackFinder.findTracks(strip("Audio 1", [0xAB, 0, 0, 0x45, 0, 0, 0, 0])).isEmpty)
    }

    func testActivityFromDescriptorBitOrByte4() {
        XCTAssertEqual(TrackFinder.findTracks(strip("T", [0xAB, 0, 0x04, 0xC5, 0, 0, 0, 0])).first?.isActive, true)
        XCTAssertEqual(TrackFinder.findTracks(strip("T", [0xAB, 0, 0x00, 0xC5, 1, 0, 0, 0])).first?.isActive, true)
        XCTAssertEqual(TrackFinder.findTracks(strip("T", [0xAB, 0, 0x00, 0xC5, 0, 0, 0, 0])).first?.isActive, false)
    }

    func testSkipsEmptyOrWhitespaceOnlyNames() {
        XCTAssertTrue(TrackFinder.findTracks(strip("")).isEmpty)
        XCTAssertTrue(TrackFinder.findTracks(strip("   ")).isEmpty)
    }

    func testReturnsMultipleTracksInOffsetOrder() {
        let t = TrackFinder.findTracks(strip("Audio 1") + strip("Audio 2") + strip("Inst 1", [0x29, 0, 0xF3, 0xC5, 0, 0, 0, 0]))
        XCTAssertEqual(t.map(\.name), ["Audio 1", "Audio 2", "Inst 1"])
        XCTAssertEqual(t.map(\.offset), t.map(\.offset).sorted())
    }

    // MARK: assignAUs

    func testAssignsEffectsToNearestPrecedingTrack() {
        var tracks = [track("Audio 1", .audio, offset: 10), track("Audio 2", .audio, offset: 100)]
        TrackFinder.assignAUs(&tracks, [au("aufx", offset: 50), au("aufx", "wxyz", offset: 150)])
        XCTAssertEqual(tracks[0].audioFx.map(\.subtype), ["abcd"])
        XCTAssertEqual(tracks[1].audioFx.map(\.subtype), ["wxyz"])
    }

    func testMidiEffectsAndProcessorsGoToMidiFx() {
        var tracks = [track("Inst 1", .instrument, offset: 10)]
        TrackFinder.assignAUs(&tracks, [au("aumf", offset: 20), au("aumi", offset: 30)])
        XCTAssertEqual(tracks[0].midiFx.count, 2)
        XCTAssertTrue(tracks[0].audioFx.isEmpty)
    }

    func testInstrumentOnlyAttachesToInstrumentTracksAndFirstWins() {
        var tracks = [track("Inst 1", .instrument, offset: 10), track("Audio 1", .audio, offset: 100)]
        TrackFinder.assignAUs(&tracks, [au("aumu", "one1", offset: 20), au("aumu", "two2", offset: 30), au("aumu", "aud1", offset: 120)])
        XCTAssertEqual(tracks[0].instrument?.subtype, "one1")
        XCTAssertNil(tracks[1].instrument)
    }

    func testDropsAUsPrecedingAllTracksAndEmptyListIsNoOp() {
        var tracks = [track("Audio 1", .audio, offset: 100)]
        TrackFinder.assignAUs(&tracks, [au("aufx", offset: 5)])
        XCTAssertTrue(tracks[0].audioFx.isEmpty)
        var none: [Track] = []
        TrackFinder.assignAUs(&none, [au("aufx", offset: 5)])
        XCTAssertTrue(none.isEmpty)
    }

    func testAssignAUsSortsTracksByOffset() {
        var tracks = [track("B", .audio, offset: 100), track("A", .audio, offset: 10)]
        TrackFinder.assignAUs(&tracks, [au("aufx", offset: 50)])
        XCTAssertEqual(tracks.map(\.name), ["A", "B"])
        XCTAssertEqual(tracks[0].audioFx.count, 1)
    }

    // MARK: assignUserNames

    func testClusterNamesNearestPrecedingTrackWithoutOverwriting() {
        var tracks = [track("Audio 1", .audio, offset: 10), track("Audio 2", .audio, offset: 100, user: "Keep")]
        let clusters = [RegionCluster(baseName: "Lead Vox", firstOffset: 50, lastOffset: 60, count: 1),
                        RegionCluster(baseName: "Other", firstOffset: 150, lastOffset: 160, count: 1)]
        TrackFinder.assignUserNames(&tracks, clusters)
        XCTAssertEqual(tracks[0].userName, "Lead Vox")
        XCTAssertEqual(tracks[1].userName, "Keep")
    }

    func testAutoNamedAndEarlyClustersAreIgnored() {
        var tracks = [track("Audio 1", .audio, offset: 100)]
        TrackFinder.assignUserNames(&tracks, [RegionCluster(baseName: "Audio 7", firstOffset: 150, lastOffset: 150, count: 1),
                                              RegionCluster(baseName: "Early", firstOffset: 5, lastOffset: 5, count: 1)])
        XCTAssertNil(tracks[0].userName)
    }

    // MARK: assignRegistryNames

    private func entry(_ name: String, _ kind: TrackKind, strip: UInt16, offset: Int = 0) -> TrackRegistryEntry {
        TrackRegistryEntry(offset: offset, name: name, kind: kind, trackID: 0, stripID: strip)
    }

    func testAudioPairedByStripIDNotOrder() {
        var tracks = [track("Audio 1", .audio, offset: 10), track("Audio 2", .audio, offset: 20)]
        TrackFinder.assignRegistryNames(&tracks, [entry("Second", .audio, strip: 2), entry("First", .audio, strip: 1)])
        XCTAssertEqual(tracks.map(\.userName), ["First", "Second"])
    }

    func testAudioSkipsDefaultEchoesOversizedIDsAndExistingNames() {
        var tracks = [track("Audio 1", .audio, offset: 10), track("Audio 2", .audio, offset: 20), track("Audio 3", .audio, offset: 30, user: "Mine")]
        TrackFinder.assignRegistryNames(&tracks, [entry("Audio 1", .audio, strip: 1), entry("Song Title", .audio, strip: 99), entry("Overwrite", .audio, strip: 3)])
        XCTAssertEqual(tracks.map(\.userName), [nil, nil, "Mine"])
    }

    func testInstrumentPairedByStorageOrdinalAndInactiveSkipped() {
        var tracks = [track("Audio 1", .audio, offset: 10), track("Inst 1", .instrument, offset: 20), track("Inst 2", .instrument, offset: 30, active: false)]
        TrackFinder.assignRegistryNames(&tracks, [entry("Piano", .instrument, strip: 2), entry("Ghost", .instrument, strip: 3), entry("Wrong", .instrument, strip: 1)])
        XCTAssertEqual(tracks.map(\.userName), [nil, "Piano", nil])
    }

    func testEmptyInputsAreNoOps() {
        var empty: [Track] = []
        TrackFinder.assignRegistryNames(&empty, [entry("X", .audio, strip: 1)])
        var tracks = [track("Audio 1", .audio, offset: 10)]
        TrackFinder.assignRegistryNames(&tracks, [])
        XCTAssertNil(tracks[0].userName)
    }

    func testParseAudioStripNumber() {
        XCTAssertEqual(TrackFinder.parseAudioStripNumber("Audio 3"), 3)
        XCTAssertEqual(TrackFinder.parseAudioStripNumber("Audio  12 "), 12)
        XCTAssertNil(TrackFinder.parseAudioStripNumber("Inst 3"))
        XCTAssertNil(TrackFinder.parseAudioStripNumber("Audio x"))
    }

    // MARK: synthesizeFolderTracks

    func testSynthesizesFolderAndSummingStackTracksIdempotently() {
        var tracks = [track("Audio 1", .audio, offset: 10)]
        let reg = [entry("Backline", .folder, strip: 0, offset: 5), entry("Sub 1", .summingStack, strip: 0, offset: 50), entry("Piano", .instrument, strip: 1, offset: 70)]
        TrackFinder.synthesizeFolderTracks(&tracks, reg)
        TrackFinder.synthesizeFolderTracks(&tracks, reg)
        XCTAssertEqual(tracks.map(\.name), ["Backline", "Audio 1", "Sub 1"])
        XCTAssertEqual(tracks.map(\.kind), [.folder, .audio, .summingStack])
        XCTAssertEqual(tracks[0].userName, "Backline")
        XCTAssertTrue(tracks[0].isActive)
    }

    func testSynthesizeSkipsOffsetCollisions() {
        var tracks = [track("Audio 1", .audio, offset: 10)]
        TrackFinder.synthesizeFolderTracks(&tracks, [entry("Dup", .folder, strip: 0, offset: 10)])
        XCTAssertEqual(tracks.count, 1)
    }
}
