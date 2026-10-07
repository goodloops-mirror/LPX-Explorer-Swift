import XCTest
@testable import LpxCore

final class AlternativesTests: XCTestCase {
    private func plist(_ body: String) -> Data {
        Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict>\(body)</dict></plist>
        """.utf8)
    }

    private func names(_ key: String, _ pairs: [(String, String)]) -> String {
        "<key>\(key)</key><dict>" + pairs.map { "<key>\($0.0)</key><string>\($0.1)</string>" }.joined() + "</dict>"
    }

    // MARK: manifest

    func testParsesTwoVariantsWithActiveFlag() throws {
        let data = plist(names("VariantNames", [("0", "Original"), ("1", "Alt Mix")]) + "<key>ActiveVariant</key><integer>1</integer>")
        let alts = try AlternativesManifest.parse(data, bundleName: "song")
        XCTAssertEqual(alts.map(\.index), [0, 1])
        XCTAssertEqual(alts.map(\.displayName), ["Original", "Alt Mix"])
        XCTAssertEqual(alts.map(\.isActive), [false, true])
    }

    func testActiveVariantDefaultsToZero() throws {
        let alts = try AlternativesManifest.parse(plist(names("VariantNames", [("0", "Only")])), bundleName: "song")
        XCTAssertEqual(alts.count, 1)
        XCTAssertEqual(alts.first?.isActive, true)
    }

    func testSubstitutesProjectNamePlaceholderInV2() throws {
        let alts = try AlternativesManifest.parse(plist(names("VariantNamesV2", [("0", "{PROJECT_NAME}")])), bundleName: "Drum Loops live")
        XCTAssertEqual(alts.first?.displayName, "Drum Loops live")
    }

    func testFallsBackToV1WhenV2AbsentOrEmpty() throws {
        let v1 = names("VariantNames", [("0", "old project")])
        XCTAssertEqual(try AlternativesManifest.parse(plist(v1), bundleName: "x").first?.displayName, "old project")
        let emptyV2 = plist("<key>VariantNamesV2</key><dict/>" + names("VariantNames", [("0", "real name")]))
        XCTAssertEqual(try AlternativesManifest.parse(emptyV2, bundleName: "x").first?.displayName, "real name")
    }

    func testEmptyWhenNoVariantKeys() throws {
        XCTAssertTrue(try AlternativesManifest.parse(plist("<key>Other</key><string>x</string>"), bundleName: "x").isEmpty)
    }

    func testSortsByNumericIndexNotStringOrder() throws {
        let data = plist(names("VariantNames", [("10", "ten"), ("2", "two"), ("0", "zero")]))
        XCTAssertEqual(try AlternativesManifest.parse(data, bundleName: "x").map(\.index), [0, 2, 10])
    }

    func testSkipsNonNumericKeys() throws {
        let data = plist(names("VariantNames", [("0", "kept"), ("abc", "dropped")]))
        XCTAssertEqual(try AlternativesManifest.parse(data, bundleName: "x").map(\.displayName), ["kept"])
    }

    func testRejectsNonDictionaryRootAndGarbage() {
        XCTAssertThrowsError(try AlternativesManifest.parse(Data("<?xml version=\"1.0\"?><plist version=\"1.0\"><array/></plist>".utf8), bundleName: "x"))
        XCTAssertThrowsError(try AlternativesManifest.parse(Data("junk".utf8), bundleName: "x"))
    }

    func testLastSavedFrom() {
        XCTAssertEqual(AlternativesManifest.lastSavedFrom(plist("<key>LastSavedFrom</key><string>Logic Pro 12.2 (6644)</string>")), "Logic Pro 12.2 (6644)")
        XCTAssertNil(AlternativesManifest.lastSavedFrom(plist("")))
        XCTAssertNil(AlternativesManifest.lastSavedFrom(Data("not a plist".utf8)))
    }

    // MARK: bundle level

    private func addManifest(_ bundle: URL, _ body: String) throws {
        let dir = bundle.appendingPathComponent("Resources")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try plist(body).write(to: ProjectBundle.informationPlistURL(bundle))
    }

    private func addAlternative(_ bundle: URL, _ index: Int, windowImage: Bool = false) throws {
        let dir = bundle.appendingPathComponent(String(format: "Alternatives/%03d", index))
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("pd".utf8).write(to: dir.appendingPathComponent("ProjectData"))
        if windowImage { try Data("jpg".utf8).write(to: dir.appendingPathComponent("WindowImage.jpg")) }
    }

    func testBundleNameStripsExtension() {
        XCTAssertEqual(ProjectBundle.bundleName(URL(fileURLWithPath: "/x/new idea.logicx")), "new idea")
        XCTAssertEqual(ProjectBundle.bundleName(URL(fileURLWithPath: "/x/Loud.LOGICX")), "Loud")
    }

    func testListsManifestAlternativesWithWindowImageAndSaveTime() throws {
        let dir = try Fixture.tempDir()
        let bundle = dir.appendingPathComponent("song.logicx")
        try addManifest(bundle, names("VariantNamesV2", [("0", "{PROJECT_NAME}"), ("1", "Alt")]) + "<key>ActiveVariant</key><integer>1</integer>")
        try addAlternative(bundle, 0, windowImage: true)
        try addAlternative(bundle, 1)

        let alts = ProjectBundle.alternatives(of: bundle)

        XCTAssertEqual(alts.map(\.displayName), ["song", "Alt"])
        XCTAssertEqual(alts.map(\.isActive), [false, true])
        XCTAssertEqual(alts.first?.windowImagePath, bundle.appendingPathComponent("Alternatives/000/WindowImage.jpg").path)
        XCTAssertNil(alts.last?.windowImagePath)
        XCTAssertGreaterThan(alts.first?.lastSavedUnix ?? 0, 0)
    }

    func testSynthesisesSingleAlternativeWhenManifestMissing() throws {
        let dir = try Fixture.tempDir()
        let bundle = try Fixture.logicx(in: dir, name: "nomanifest.logicx")

        let alts = ProjectBundle.alternatives(of: bundle)

        XCTAssertEqual(alts.map(\.displayName), ["nomanifest"])
        XCTAssertEqual(alts.map(\.isActive), [true])
        XCTAssertFalse(ProjectBundle.hasInformationPlist(bundle))
        XCTAssertNil(ProjectBundle.lastSavedFrom(bundle: bundle))
    }

    func testEmptyWhenNoManifestAndNoProjectData() throws {
        let dir = try Fixture.tempDir()
        let bundle = dir.appendingPathComponent("empty.logicx")
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
        XCTAssertTrue(ProjectBundle.alternatives(of: bundle).isEmpty)
    }

    func testReadsLastSavedFromThroughBundle() throws {
        let dir = try Fixture.tempDir()
        let bundle = dir.appendingPathComponent("v.logicx")
        try addManifest(bundle, "<key>LastSavedFrom</key><string>Logic Pro 11.2.2 (6387)</string>")
        XCTAssertTrue(ProjectBundle.hasInformationPlist(bundle))
        XCTAssertEqual(ProjectBundle.lastSavedFrom(bundle: bundle), "Logic Pro 11.2.2 (6387)")
    }
}
