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
        // The names are the same except where the project itself changed between the two saves (a Diva patch name).
        let differing = zip(old, new).filter { $0.displayName != $1.displayName }.map { "\($0.displayName) | \($1.displayName)" }
        XCTAssertEqual(differing.count, 1, "\(differing)")
        XCTAssertEqual(old.first?.displayName, "CUE")
    }

    func testOlderFileKeepsItsOwnPluginsAndTheNewerOnesThose() throws {
        // The two saves really do differ here (Kontakt 5 vs 7 ids): each file reports what it contains.
        let old = try tracks("LSK The Others v10.logicx"), new = try tracks("LSK The Others v10 saved with Logic 11.2.2.logicx")
        func ids(_ list: [Track]) -> Set<String> { Set(list.flatMap { ([$0.instrument].compactMap { $0 } + $0.audioFx).map(\.subtype) }) }
        XCTAssertTrue(ids(old).contains("NiO5"))
        XCTAssertTrue(ids(new).contains("NiK8"))
    }
}
