import XCTest
@testable import LpxCore

/// The track list checked against what Logic itself displays (the owner's screenshots of `example_projects`).
/// Names are never used as identifiers — only to compare with what the screenshots show.
final class GoldenArrangementTests: XCTestCase {
    private func tracks(_ bundle: String) throws -> [Track] {
        let url = Golden.projectsDir.appendingPathComponent("\(bundle)/Alternatives/000/ProjectData")
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { throw XCTSkip("example project missing: \(bundle)") }
        return data.withUnsafeBytes { raw -> [Track] in
            let bytes = raw.bindMemory(to: UInt8.self)
            return TrackPipeline.tracks(in: bytes, aus: AUFinder.findAUs(in: bytes))
        }
    }

    /// (prefix, suffix) as far as the screenshot shows the name; suffix "" ⇒ the name is fully visible and must be exact.
    private typealias Shown = (prefix: String, suffix: String)

    private func check(_ t: Track?, _ shown: Shown, _ label: String, file: StaticString = #filePath, line: UInt = #line) {
        guard let name = t?.displayName else { return XCTFail("\(label): no such track", file: file, line: line) }
        if shown.suffix.isEmpty { XCTAssertTrue(name == shown.prefix || name.hasPrefix(shown.prefix + " ") && shown.prefix.count >= 0 && name.trimmingCharacters(in: .whitespaces) == shown.prefix, "\(label): '\(name)' vs '\(shown.prefix)'", file: file, line: line) }
        else { XCTAssertTrue(name.hasPrefix(shown.prefix) && name.hasSuffix(shown.suffix), "\(label): '\(name)' vs '\(shown.prefix)…\(shown.suffix)'", file: file, line: line) }
    }

    // MARK: To The Mountains v01 (46 tracks + the two the owner added), in the moved state

    func testNumberedProjectListsEveryTrackInLogicsOrder() throws {
        let list = try tracks("AQU 14m16 [260306] To The Mountains v01.logicx")
        XCTAssertEqual(list.count, 47)
        XCTAssertEqual(list.map(\.position), Array(1...47).map { Optional($0) })
        let shown: [Shown] = [
            ("DX", ""), ("FX", ""), ("MX", ""), ("CUE", ""), ("EP 11 -", "IC AAF"), ("Audio 6", ""), ("Audio 7", ""), ("Audio 8", ""), ("Audio 9", ""), ("PIANO", ""),
            ("AQU T", "ordian"), ("Tranqu", "andeur"), ("SYNTHS", ""), ("AQU T", "eremin"), ("HARP", ""), ("Harp 1", ""), ("GTR", ""), ("AQU T", "be lyre"), ("WOODS", ""),
            ("AQU T", "flute"), ("AQU T", "larinet"), ("AQU T", "larinet"), ("AQU T", "ocarina"), ("BRASS", ""), ("AQU T", "cornet"), ("SOLO STR", ""),
            ("AQU In", "l Tk#01"), ("AQU In", "Tk#02"), ("STR", ""), ("ALB5 F", "do Sus"), ("BH Harmonics", ""), ("AQU In", "l Tk#01"), ("Audio 33", ""),
            ("AQU In", "Tk#04"), ("AQU In", "Tk#05"), ("Audio 34", ""), ("CHOIR", ""), ("NOVEL", "oir Evo"), ("AQU In", "Tk#02"), ("AQU In", "Tk#05"), ("AQU In", "Tk#08"),
            ("SYNTH", "LLETS"), ("Vibra", ""), ("Vibra", ""), ("MALLETS", ""),
        ]
        for (i, s) in shown.enumerated() { check(list[i], s, "track \(i + 1)") }
    }

    func testTwoTracksOnOneObjectHaveTheirOwnNames() throws {
        let list = try tracks("AQU 14m16 [260306] To The Mountains v01.logicx")
        XCTAssertEqual(list[45].userName, "ZZZ-RENAMED-OBJECT-TRACK-46")
        XCTAssertEqual(list[46].userName, "ZZZ-RENAMED-OBJECT-TRACK-47")
        XCTAssertEqual(list[45].objectName, "ZZZ-RENAMED-OBJECT-AUDIO-9")
        XCTAssertEqual(list[46].objectName, "ZZZ-RENAMED-OBJECT-AUDIO-9")
        XCTAssertEqual(list[45].name, list[46].name, "same object ⇒ same channel strip")
        XCTAssertFalse(list[45].name.isEmpty)
    }

    func testNumberedProjectFoldersAreFolderTracksAndNothingBelow46IsHidden() throws {
        let list = try tracks("AQU 14m16 [260306] To The Mountains v01.logicx")
        for p in [4, 5, 10, 13, 15, 17, 19, 24, 26, 29, 37, 42, 45] { XCTAssertEqual(list[p - 1].kind, .folder, "track \(p)") }
        XCTAssertEqual(list.prefix(45).filter(\.isHidden).count, 0)
    }

    // MARK: Who are you Alea v01 — rows 1…27 of its saved window image, with rows 5…15 hidden

    func testUntouchedProjectMatchesTheVisibleRowsAndHiddenTracks() throws {
        let list = try tracks("AQU 14m06 [260306] Who are you Alea v01.logicx")
        let shown: [(Int, String)] = [(1, "CUE"), (2, "DX"), (3, "FX"), (4, "MX"), (16, "INST"), (17, "PIANO"), (18, "GUITARS"), (19, "Ac. Guitars"),
                                      (20, "AQU Runion A. Git. 1 MM"), (21, "AQU Runion A. Git. 2 MM"), (22, "AQU Runion A. Git. 3 MM"),
                                      (23, "AQU Runion A. Git. 4 MM"), (24, "AQU Runion A. Git. 5 MM"), (25, "STRINGS"), (26, "Evo Strings"), (27, "Chamber Waves")]
        for (p, name) in shown { XCTAssertEqual(list[p - 1].displayName.trimmingCharacters(in: .whitespaces), name, "track \(p)") }
        XCTAssertEqual(list.prefix(27).filter(\.isHidden).compactMap(\.position), Array(5...15))
        XCTAssertEqual(list[6...14].map(\.displayName), Array(repeating: "Audio 7", count: 9), "nine tracks that share the name Audio 7")
    }

    // MARK: Please Follow me v01 — several tracks per object, folders, object-less tracks

    func testSharedObjectsFoldersAndChannels() throws {
        let list = try tracks("AQU 14m03 [260306] Please Follow me v01.logicx")
        func t(_ p: Int) -> Track { list[p - 1] }
        for p in [1, 16, 22, 32, 43, 61, 64] { XCTAssertEqual(t(p).kind, .folder, "track \(p) is a folder/banner") }
        XCTAssertEqual([t(1), t(16), t(22), t(32), t(43), t(61), t(64)].map(\.displayName), ["CUE", "PIANO", "SYNTHS", "HARP", "GTR", "WOODS", "SOLO STR"])
        // tracks 33–34, 35–36, 37–38 each pair share one object ("Harp 1", "Harp 2", "Harp 1")
        XCTAssertEqual([t(33), t(34), t(35), t(36), t(37), t(38), t(39), t(40)].map(\.displayName),
                       ["Harp 1", "Harp 1", "Harp 2", "Harp 2", "Harp 1", "Harp 1", "Harp 2", "Harp 1 Gliss"])
        XCTAssertEqual(t(33).objectName, t(34).objectName)
        XCTAssertEqual(t(33).name, "Inst 61", "the inspector in the screenshot shows Channel: Inst 61 for the selected track 33")
        XCTAssertEqual(t(33).name, t(34).name)
        XCTAssertEqual([t(29), t(30)].map(\.displayName), ["AmBell Fairy", "AmBell Fairy"])
        XCTAssertEqual([t(17), t(18), t(19), t(20), t(21)].map(\.displayName), ["The Grandeur", "The Grandeur", "The Grandeur B", "The Grandeur C", "The Grandeur D"])
        // tracks 44 and 45 share an object but show different names (screenshot: "AQU O…It HH A" vs "AQU Li…It HH A")
        XCTAssertEqual(t(44).objectName, t(45).objectName)
        XCTAssertTrue(t(44).displayName.hasPrefix("AQU O"), t(44).displayName)
        XCTAssertTrue(t(45).displayName.hasPrefix("AQU Li"), t(45).displayName)
        XCTAssertTrue(t(47).displayName.hasPrefix("AQU O"), t(47).displayName)
    }

    // MARK: The new minimal projects

    func testEmptyProjectsHaveExactlyOneTrack() throws {
        let a = try tracks("Empty - 1 Audio Track.logicx"), i = try tracks("Empty - 1 Inst Track.logicx")
        XCTAssertEqual(a.count, 1); XCTAssertEqual(i.count, 1)
        XCTAssertEqual(a.first?.position, 1); XCTAssertEqual(i.first?.position, 1)
        XCTAssertEqual(a.first?.kind, .audio); XCTAssertEqual(i.first?.kind, .instrument)
        XCTAssertEqual(a.first?.name, "Audio 1"); XCTAssertEqual(i.first?.name, "Inst 1")
    }

    // MARK: structure over every example project

    func testEveryExampleProjectHasAConsecutivelyNumberedList() throws {
        let dirs = ((try? FileManager.default.contentsOfDirectory(atPath: Golden.projectsDir.path)) ?? []).filter { $0.hasSuffix(".logicx") }.sorted()
        if dirs.isEmpty { throw XCTSkip("no example projects") }
        for d in dirs {
            let list = try tracks(d)
            XCTAssertFalse(list.isEmpty, d)
            XCTAssertEqual(list.compactMap(\.position), Array(1...list.count), "\(d): positions must be 1…N without gaps")
            XCTAssertEqual(Set(list.map(\.offset)).count, list.count, d)
            let named = list.filter { !$0.displayName.isEmpty }.count
            XCTAssertGreaterThanOrEqual(Double(named) / Double(list.count), 0.9, "\(d): \(named)/\(list.count) tracks have a name")
        }
    }
}
