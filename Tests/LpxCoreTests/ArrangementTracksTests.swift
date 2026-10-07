import XCTest
@testable import LpxCore

final class ArrangementTracksTests: XCTestCase {
    private func au(_ sub: String) -> AURef { AURef(typeCode: "aufx", subtype: sub, manufacturer: "Mfr1", offset: 0) }
    private func strip(_ name: String, _ kind: TrackKind, offset: Int, fx: [AURef] = [], instrument: AURef? = nil) -> Track {
        Track(name: name, kind: kind, offset: offset, isActive: true, instrument: instrument, audioFx: fx)
    }
    private func rec(_ position: Int, key: UInt32, name: UInt32 = 0, hidden: Bool = false) -> ArrangementRecord {
        ArrangementRecord(position: position, nameTextID: name, objectKey: key, isHidden: hidden, offset: position * 100)
    }
    private func obj(_ name: String, key: UInt32, cls: UInt16 = 0x1223, strip: UInt16) -> ObjectRecord {
        ObjectRecord(offset: 0, name: name, classNumber: cls, key: key, stripID: strip)
    }

    // 4 audio strips then 2 instrument strips, in storage order
    private var strips: [Track] {
        [strip("Audio 1", .audio, offset: 10, fx: [au("EQ  ")]), strip("Audio 2", .audio, offset: 20), strip("Audio 3", .audio, offset: 30), strip("Audio 4", .audio, offset: 40),
         strip("Inst 1", .instrument, offset: 50, instrument: AURef(typeCode: "aumu", subtype: "Synt", manufacturer: "Mfr2", offset: 0)), strip("Inst 2", .instrument, offset: 60)]
    }

    func testTrackNameComesFromItsOwnTextElseFromTheObject() {
        let tracks = ArrangementTracks.build(
            records: [rec(1, key: 0x170), rec(2, key: 0x68, name: 0x50)],
            texts: [0x50: "Lead Vox"], objects: [obj("DX", key: 0x170, strip: 1), obj("FX", key: 0x68, strip: 2)], strips: strips)
        XCTAssertEqual(tracks.map(\.userName), ["DX", "Lead Vox"])
        XCTAssertEqual(tracks.map(\.objectName), ["DX", "FX"])
        XCTAssertEqual(tracks.map(\.position), [1, 2])
    }

    func testSeveralTracksOnOneObjectShareChannelAndPluginsButKeepTheirOwnNames() {
        let tracks = ArrangementTracks.build(
            records: [rec(1, key: 0x218, name: 0xc), rec(2, key: 0x218, name: 0x1c)],
            texts: [0xc: "ZZZ-TRACK-46", 0x1c: "ZZZ-TRACK-47"], objects: [obj("ZZZ-OBJECT", key: 0x218, strip: 1)], strips: strips)
        XCTAssertEqual(tracks.map(\.userName), ["ZZZ-TRACK-46", "ZZZ-TRACK-47"])
        XCTAssertEqual(tracks.map(\.name), ["Audio 1", "Audio 1"])
        XCTAssertEqual(tracks.map(\.objectName), ["ZZZ-OBJECT", "ZZZ-OBJECT"])
        XCTAssertEqual(tracks.map { $0.audioFx.count }, [1, 1])
    }

    func testChannelKindAndPluginsComeFromTheLinkedStrip() {
        let tracks = ArrangementTracks.build(records: [rec(1, key: 1), rec(2, key: 2)], texts: [:],
                                             objects: [obj("DX", key: 1, strip: 1), obj("Piano", key: 2, cls: 0x1222, strip: 5)], strips: strips)
        XCTAssertEqual(tracks.first?.kind, .audio)
        XCTAssertEqual(tracks.first?.name, "Audio 1")
        XCTAssertEqual(tracks.first?.audioFx.map(\.subtype), ["EQ  "])
        XCTAssertEqual(tracks.last?.kind, .instrument)
        XCTAssertEqual(tracks.last?.name, "Inst 1")
        XCTAssertEqual(tracks.last?.instrument?.subtype, "Synt")
    }

    func testUnrecognisedClassesAreLinkedByTheStripIDAlone() {
        // class 0x1199 (instruments) resolves through the storage ordinal; 0x11f4 (audio) through the "Audio N" name
        let tracks = ArrangementTracks.build(records: [rec(1, key: 1), rec(2, key: 2)], texts: [:],
                                             objects: [obj("Harp 1", key: 1, cls: 0x1199, strip: 6), obj("flute", key: 2, cls: 0x11f4, strip: 3)], strips: strips)
        XCTAssertEqual(tracks.map(\.name), ["Inst 2", "Audio 3"])
        XCTAssertEqual(tracks.map(\.kind), [.instrument, .audio])
    }

    func testAnAmbiguousStripNumberIsResolvedByTheStripThatExists() {
        // trailer read as 256 (no such strip) or 3 (Audio 3 exists)
        let object = ObjectRecord(offset: 0, name: "TRACKNAME AUDIO 3", classNumber: 0x1223, key: 7, stripID: 256, altStripID: 3)
        let tracks = ArrangementTracks.build(records: [rec(1, key: 7)], texts: [:], objects: [object], strips: strips)
        XCTAssertEqual(tracks.first?.name, "Audio 3")
        XCTAssertEqual(tracks.first?.kind, .audio)
    }

    func testFolderTracksShareTheFolderObjectButHaveTheirOwnNames() {
        let tracks = ArrangementTracks.build(records: [rec(1, key: 0x10, name: 0x10), rec(2, key: 0x10, name: 0x14)], texts: [0x10: "CUE", 0x14: "PIANO"],
                                             objects: [obj("(Folder)", key: 0x10, cls: 0x1001, strip: 0)], strips: strips)
        XCTAssertEqual(tracks.map(\.kind), [.folder, .folder])
        XCTAssertEqual(tracks.map(\.userName), ["CUE", "PIANO"])
        XCTAssertEqual(tracks.map(\.name), ["", ""])
    }

    func testHiddenFlagAndPositionsAreCarriedOver() {
        let tracks = ArrangementTracks.build(records: [rec(5, key: 1, hidden: true), rec(9, key: 1)], texts: [:], objects: [obj("DX", key: 1, strip: 1)], strips: strips)
        XCTAssertEqual(tracks.map(\.isHidden), [true, false])
        XCTAssertEqual(tracks.map(\.position), [5, 9])
        XCTAssertTrue(tracks.allSatisfy(\.isActive))
    }

    func testUnknownObjectStillGivesATrackWithItsOwnNameIfAny() {
        let tracks = ArrangementTracks.build(records: [rec(1, key: 0, name: 0x20), rec(2, key: 0x999)], texts: [0x20: "Silent track"], objects: [], strips: strips)
        XCTAssertEqual(tracks.map(\.userName), ["Silent track", nil])
        XCTAssertEqual(tracks.map(\.kind), [.unknown, .unknown])
        XCTAssertEqual(tracks.count, 2)
    }

    func testRecordOffsetsBecomeUniqueTrackIdentities() {
        let tracks = ArrangementTracks.build(records: [rec(1, key: 1), rec(2, key: 1)], texts: [:], objects: [obj("DX", key: 1, strip: 1)], strips: strips)
        XCTAssertEqual(Set(tracks.map(\.offset)).count, 2)
    }
}
