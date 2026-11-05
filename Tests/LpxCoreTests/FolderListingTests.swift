import XCTest
@testable import LpxCore

final class FolderListingTests: XCTestCase {
    func testListsFoldersBeforeProjectsInNaturalOrder() throws {
        let dir = try Fixture.tempDir()
        let fm = FileManager.default
        try fm.createDirectory(at: dir.appendingPathComponent("Song 10"), withIntermediateDirectories: true)
        try fm.createDirectory(at: dir.appendingPathComponent("Song 2"), withIntermediateDirectories: true)
        try Fixture.logicx(in: dir, name: "Alpha.logicx")
        try Fixture.logicx(in: dir, name: "Beta.logicx")

        let items = FolderListing.items(in: dir)

        XCTAssertEqual(items.map(\.name), ["Song 2", "Song 10", "Alpha.logicx", "Beta.logicx"])
        XCTAssertEqual(items.map(\.kind), [.folder, .folder, .project, .project])
        XCTAssertEqual(items.first?.path, dir.appendingPathComponent("Song 2").path)
    }

    func testBundlesAreLeavesAndLegacyFilesAreProjects() throws {
        let dir = try Fixture.tempDir()
        let outer = try Fixture.logicx(in: dir, name: "Outer.logicx")
        try Fixture.logicx(in: outer, name: "Inner.logicx")
        try Data("x".utf8).write(to: dir.appendingPathComponent("Old.lso"))

        let items = FolderListing.items(in: dir)

        XCTAssertEqual(items.map(\.name), ["Old.lso", "Outer.logicx"])
        XCTAssertTrue(items.allSatisfy { $0.kind == .project })
    }

    func testSkipsFilesHiddenItemsAndSymlinks() throws {
        let dir = try Fixture.tempDir()
        let fm = FileManager.default
        try Data("x".utf8).write(to: dir.appendingPathComponent("mix.wav"))
        try fm.createDirectory(at: dir.appendingPathComponent(".hidden"), withIntermediateDirectories: true)
        let real = dir.appendingPathComponent("Real")
        try fm.createDirectory(at: real, withIntermediateDirectories: true)
        try fm.createSymbolicLink(at: dir.appendingPathComponent("Link"), withDestinationURL: real)

        XCTAssertEqual(FolderListing.items(in: dir).map(\.name), ["Real"])
    }

    func testUnreadableOrMissingFolderIsEmpty() {
        XCTAssertEqual(FolderListing.items(in: URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)")), [])
    }

    func testChainListsEveryLevelBelowTheRoot() {
        XCTAssertEqual(FolderListing.chain(to: "/r/a/b/p.logicx", under: "/r"), ["/r/a", "/r/a/b", "/r/a/b/p.logicx"])
        XCTAssertEqual(FolderListing.chain(to: "/r/p.logicx", under: "/r/"), ["/r/p.logicx"])
    }

    func testChainIsNilOutsideTheRoot() {
        XCTAssertNil(FolderListing.chain(to: "/r", under: "/r"))
        XCTAssertNil(FolderListing.chain(to: "/rx/p.logicx", under: "/r"))
        XCTAssertNil(FolderListing.chain(to: "/other/p.logicx", under: "/r"))
    }
}
