import XCTest
@testable import LpxCore

final class TrackPipelineTests: XCTestCase {
    private typealias F = ArrangementFixture

    /// Channel strip: NUL, 16-byte name field, 8-byte descriptor (active audio unless `inst`).
    private func strip(_ name: String, inst: Bool = false) -> [UInt8] {
        let f = [0x20] + Array(name.utf8)
        let desc: [UInt8] = inst ? [0x29, 0x00, 0xF3, 0xC5, 0x01, 0, 0, 0] : [0xAB, 0x00, 0x04, 0xC5, 0, 0, 0, 0]
        return [0x00] + f + [UInt8](repeating: 0, count: 16 - f.count) + desc
    }

    /// Registry-shaped object record preceded by the 170-byte header holding its key twice; trailer carries the strip id.
    private func object(name: String, key: UInt32, stripID: UInt8) -> [UInt8] {
        var head = [UInt8](repeating: 0x11, count: 170)
        head.replaceSubrange(0..<4, with: F.u32(key)); head.replaceSubrange(42..<46, with: F.u32(key))
        let rec: [UInt8] = [0, 0, 0, 0, 0x23, 0x12, 0, 0, 0, 0, 0xAB, 0xCD, 0, 0, UInt8(name.utf8.count), 0] + Array(name.utf8)
        return head + rec + [stripID, 0, 0, 0, 0, 1, 0, 0]
    }

    private let noise = [UInt8](repeating: 0x11, count: 60)

    func testTracksComeFromTheArrangementListWithOwnNamesObjectsAndHiddenFlags() {
        var raw: [UInt8] = strip("Audio 1")
        raw += strip("Audio 2")
        raw += object(name: "DX", key: 0x170, stripID: 1)
        raw += object(name: "FX", key: 0x68, stripID: 2)
        raw += F.text(id: 0x40, "DX second take")
        raw += noise
        raw += F.record(index: 0, key: 0x170)
        raw += F.record(index: 1, nameID: 0x40, key: 0x170)
        raw += F.record(index: 2, key: 0x68, hidden: true)
        raw += F.record(index: 3, nameID: 0x30, key: 0x50, type: 3)

        let tracks = TrackPipeline.tracks(raw, aus: [])

        XCTAssertEqual(tracks.map(\.position), [1, 2, 3])
        XCTAssertEqual(tracks.map(\.userName), ["DX", "DX second take", "FX"])
        XCTAssertEqual(tracks.map(\.name), ["Audio 1", "Audio 1", "Audio 2"], "channel = the object's strip")
        XCTAssertEqual(tracks.map(\.objectName), ["DX", "DX", "FX"])
        XCTAssertEqual(tracks.map(\.isHidden), [false, false, true])
    }

    func testPluginsOfTheObjectsStripAppearOnItsTracks() {
        var raw: [UInt8] = strip("Audio 1")
        raw += Array("PADDING_".utf8) + Array("nooT".utf8)
        raw += Array("xfua".utf8) + Array("pmoC".utf8)          // aufx / Comp / Toon, right after the strip
        raw += [0, 0, 0xff, 0xff, 0, 0, 0, 0]
        raw += object(name: "DX", key: 0x170, stripID: 1)
        raw += noise
        raw += F.record(index: 0, key: 0x170)
        let found = AUFinder.findAUs(raw)

        let tracks = TrackPipeline.tracks(raw, aus: found)

        XCTAssertEqual(tracks.first?.audioFx.map(\.fingerprint), ["aufx/Comp/Toon"])
    }

    func testWithoutAnArrangementListItFallsBackToTheFilteredChannelStrips() {
        var raw: [UInt8] = strip("Audio 1")
        raw += strip("Inst 1", inst: true)
        raw += noise
        let tracks = TrackPipeline.tracks(raw, aus: [])
        XCTAssertEqual(tracks.map(\.name), ["Audio 1", "Inst 1"])
        XCTAssertTrue(tracks.allSatisfy { $0.position == nil })
    }

    func testRelevantKeepsTheFieldsOfArrangementTracks() {
        var t = Track(name: "Audio 1", kind: .audio, offset: 1, isActive: true)
        t.position = 4; t.isHidden = true
        let kept = TrackPipeline.relevant([t]).first
        XCTAssertEqual(kept?.position, 4)
        XCTAssertEqual(kept?.isHidden, true)
    }
}
