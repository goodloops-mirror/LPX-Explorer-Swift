import XCTest
@testable import LpxCore

final class LogicxDiscoveryTests: XCTestCase {
    func testFindsBundlesInFlatDirectory() throws {
        let dir = try Fixture.tempDir()
        let a = try Fixture.logicx(in: dir, name: "alpha.logicx")
        let b = try Fixture.logicx(in: dir, name: "beta.logicx")

        let found = try LogicxDiscovery.discover(in: dir)

        XCTAssertEqual(Set(found.map(\.path)), Set([a.path, b.path]))
    }

    func testDescendsIntoNestedFoldersAndIgnoresFiles() throws {
        let dir = try Fixture.tempDir()
        let nested = dir.appendingPathComponent("a/b")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        let deep = try Fixture.logicx(in: nested, name: "deep.logicx")
        try Data("x".utf8).write(to: dir.appendingPathComponent("song.wav"))

        let found = try LogicxDiscovery.discover(in: dir)

        XCTAssertEqual(found.map(\.path), [deep.path])
    }

    func testDoesNotRecurseIntoBundles() throws {
        let dir = try Fixture.tempDir()
        let outer = try Fixture.logicx(in: dir, name: "outer.logicx")
        try Fixture.logicx(in: outer, name: "trap.logicx")

        let found = try LogicxDiscovery.discover(in: dir)

        XCTAssertEqual(found.map(\.path), [outer.path])
    }

    func testMatchesExtensionCaseInsensitively() throws {
        let dir = try Fixture.tempDir()
        let b = try Fixture.logicx(in: dir, name: "Loud.LOGICX")

        XCTAssertEqual(try LogicxDiscovery.discover(in: dir).map(\.path), [b.path])
    }

    func testMissingRootThrowsNotFound() {
        XCTAssertThrowsError(try LogicxDiscovery.discover(in: URL(fileURLWithPath: "/no/such/lpx-dir"))) {
            XCTAssertEqual($0 as? DiscoveryError, .notFound("/no/such/lpx-dir"))
        }
    }

    func testCancelledWalkReturnsNothing() throws {
        let dir = try Fixture.tempDir()
        try Fixture.logicx(in: dir, name: "ignored.logicx")

        XCTAssertTrue(try LogicxDiscovery.discover(in: dir, isCancelled: { true }).isEmpty)
    }
}
