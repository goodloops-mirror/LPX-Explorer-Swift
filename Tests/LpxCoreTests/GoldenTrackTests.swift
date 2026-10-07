import XCTest
@testable import LpxCore

final class GoldenTrackTests: XCTestCase {
    private func describe(_ au: AURef?) -> String { au.map { "\($0.fingerprint)@\($0.offset)" } ?? "-" }

    private func describe(_ t: Track) -> String {
        [t.name, t.userName ?? "-", t.kind.rawValue, "\(t.offset)", "\(t.isActive)", describe(t.instrument),
         t.midiFx.map { describe($0) }.joined(separator: ","), t.audioFx.map { describe($0) }.joined(separator: ",")].joined(separator: "|")
    }

    /// `rejected`: Rust AUs the Swift parser deliberately drops (text-blob noise); they are removed from
    /// the oracle's tracks too, so everything else must still match exactly.
    private func describe(_ j: [String: Any], rejected: Set<String>) -> String {
        func id(_ d: [String: Any]) -> String { "\(d["type_code"]!)/\(d["subtype"]!)/\(d["manufacturer"]!)@\(d["offset"]!)" }
        func au(_ a: Any?) -> String {
            guard let d = a as? [String: Any], !rejected.contains(id(d)) else { return "-" }
            return id(d)
        }
        func list(_ a: Any?) -> String { (a as! [[String: Any]]).filter { !rejected.contains(id($0)) }.map { au($0) }.joined(separator: ",") }
        return [j["name"] as! String, j["user_name"] as? String ?? "-", j["kind"] as! String, "\(j["offset"]!)",
                "\(j["is_active"] as! Bool)", au(j["instrument"]), list(j["midi_fx"]), list(j["audio_fx"])].joined(separator: "|")
    }

    /// Whole pipeline must reproduce the Rust oracle's tracks (names, user names, kinds,
    /// activity and AU assignment) on every real example project.
    func testTrackPipelineMatchesRustOracleOnExampleProjects() throws {
        var total = 0
        for c in try Golden.cases() {
            let aus = AUFinder.findAUs(c.projectData)
            let found = Set(aus.map { "\($0.fingerprint)@\($0.offset)" })
            let rejected = Set((c.json["aus"] as! [[String: Any]]).compactMap { d -> String? in
                let k = "\(d["type_code"]!)/\(d["subtype"]!)/\(d["manufacturer"]!)@\(d["offset"]!)"
                return found.contains(k) ? nil : k
            })
            let actual = TrackPipeline.channelStrips(c.projectData, aus: aus).map(describe)
            let expected = (c.json["tracks"] as! [[String: Any]]).map { describe($0, rejected: rejected) }
            total += expected.count
            XCTAssertEqual(actual.count, expected.count, "\(c.name): track count")
            for (a, e) in zip(actual, expected) where a != e { XCTFail("\(c.name)\n  swift: \(a)\n  rust:  \(e)"); break }
        }
        XCTAssertGreaterThan(total, 1000, "expected a realistic corpus")
    }

    func testRegistryAndRegionsMatchRustOracle() throws {
        for c in try Golden.cases() {
            let reg = TrackRegistry.findRecords(c.projectData)
            let expected = c.json["registry"] as! [[String: Any]]
            XCTAssertEqual(reg.map { "\($0.name)|\($0.kind.rawValue)|\($0.offset)|\($0.trackID)|\($0.stripID)" },
                           expected.map { "\($0["name"]!)|\($0["kind"]!)|\($0["offset"]!)|\($0["track_id"]!)|\($0["strip_id"]!)" }, c.name)
            XCTAssertEqual(Regions.findRecords(c.projectData).count, c.json["regions"] as? Int, "\(c.name) regions")
            XCTAssertEqual(Regions.cluster(Regions.findRecords(c.projectData)).count, c.json["clusters"] as? Int, "\(c.name) clusters")
        }
    }
}
