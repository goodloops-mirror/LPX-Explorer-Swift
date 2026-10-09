import XCTest
@testable import LpxCore

/// "LSK The Others v10" was saved with Logic Pro X 10.5.1 (older record layout: 92-byte track records, object records packed
/// behind the previous text); the same project re-saved with Logic Pro 11.2.2 is the ground truth for what its tracks are.
final class GoldenLegacyFormatTests: XCTestCase {
    private func tracks(_ bundle: String) throws -> [Track] {
        let url = Golden.projectsDir.appendingPathComponent("\(bundle)/Alternatives/000/ProjectData")
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { throw XCTSkip("example project missing: \(bundle)") }
        return data.withUnsafeBytes { raw -> [Track] in
            let bytes = raw.bindMemory(to: UInt8.self)
            return TrackPipeline.tracks(in: bytes, aus: AUFinder.findAUs(in: bytes))
        }
    }

    func testOlderFileListsTheSameTracksAsItsResavedTwin() throws {
        let old = try tracks("LSK The Others v10.logicx")
        let new = try tracks("LSK The Others v10 saved with Logic 11.2.2.logicx")
        XCTAssertEqual(new.count, 111)
        XCTAssertEqual(old.count, new.count)
        XCTAssertEqual(old.map(\.position), Array(1...111).map { Optional($0) })
        XCTAssertEqual(old.map(\.isHidden), new.map(\.isHidden))
        XCTAssertEqual(old.filter(\.isHidden).count, 54)
        XCTAssertEqual(old.map(\.kind), new.map(\.kind), "folders, audio and instrument tracks are recognised alike")
        XCTAssertEqual(old.map(\.name), new.map(\.name), "channel names (Audio 5, Inst 12, …)")
        // The names are the same except two instrument tracks named after their plug-in preset (Diva, Hive), which differ
        // between the two saves: Logic reports the current preset name when it re-saves.
        let differing = zip(old, new).filter { $0.displayName != $1.displayName }
        XCTAssertEqual(differing.map(\.1.position), [54, 52].sorted().map { Optional($0) }, "\(differing.map { "\($0.displayName) | \($1.displayName)" })")
        XCTAssertTrue(differing.allSatisfy { $0.0.kind == .instrument && $0.1.kind == .instrument })
        // Track 52 (hidden) used to come out blank in both files; both now resolve to the Hive instrument track.
        XCTAssertEqual(old[51].instrument?.subtype, "hIVE"); XCTAssertEqual(new[51].instrument?.subtype, "hIVE")
        XCTAssertFalse(old[51].displayName.isEmpty); XCTAssertFalse(new[51].displayName.isEmpty)
        XCTAssertEqual(old.first?.displayName, "CUE")
    }

    func testOlderFileKeepsItsOwnPluginsAndTheNewerOnesThose() throws {
        // The two saves really do differ here (Kontakt 5 vs 7 ids): each file reports what it contains.
        let old = try tracks("LSK The Others v10.logicx"), new = try tracks("LSK The Others v10 saved with Logic 11.2.2.logicx")
        func ids(_ list: [Track]) -> Set<String> { Set(list.flatMap { ([$0.instrument].compactMap { $0 } + $0.audioFx).map(\.subtype) }) }
        XCTAssertTrue(ids(old).contains("NiO5"))
        XCTAssertTrue(ids(new).contains("NiK8"))
    }

    /// "Spacey" (2005, Logic 7) re-saved with Logic Pro 11.2.2: the arrange window as Logic shows it (owner's screenshot).
    func testConvertedProjectShowsEveryTrackNameAsLogicDoes() throws {
        let list = try tracks("Spacey saved with Logic 11.2.2.logicx")
        XCTAssertEqual(list.map(\.position), Array(1...11).map { Optional($0) })
        XCTAssertEqual(list.map(\.displayName), ["Mix", "zz Audio 002", "zz Audio 003", "zz Audio 004",
                                                  "zz AudioInst 01", "zz AudioInst 02", "zz AudioInst 03", "zz AudioInst 04",
                                                  "Bus 1", "Bus 2", "Resources"])
        XCTAssertEqual(list.last?.kind, .folder)
        XCTAssertTrue(list.allSatisfy { !$0.isHidden })
    }
}
