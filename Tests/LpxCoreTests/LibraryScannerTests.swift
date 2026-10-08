import XCTest
@testable import LpxCore

private final class Box<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: T
    init(_ v: T) { value = v }
    func with<R>(_ f: (inout T) -> R) -> R { lock.lock(); defer { lock.unlock() }; return f(&value) }
}

final class LibraryScannerTests: XCTestCase {
    func testWorkerCountIsSeventyPercentOfCoresWithFloorOfOne() {
        XCTAssertEqual(LibraryScanner.defaultWorkerCount(cores: 20), 14)
        XCTAssertEqual(LibraryScanner.defaultWorkerCount(cores: 10), 7)
        XCTAssertEqual(LibraryScanner.defaultWorkerCount(cores: 4), 2)
        XCTAssertEqual(LibraryScanner.defaultWorkerCount(cores: 1), 1)
    }

    func testEveryBundleProducesExactlyOneOutcome() async throws {
        let dir = try Fixture.tempDir()
        let bundles = try (0..<25).map { try Fixture.logicx(in: dir, name: "p\($0).logicx") }
        let seen = Box<[String]>([])

        await LibraryScanner.scan(bundles: bundles, workers: 4) { outcome in
            if case let .parsed(s) = outcome { seen.with { $0.append(s.path) } }
        }

        XCTAssertEqual(Set(seen.with { $0 }), Set(bundles.map(\.path)))
        XCTAssertEqual(seen.with { $0.count }, 25)
    }

    func testConcurrencyNeverExceedsWorkersButUsesThem() async throws {
        let dir = try Fixture.tempDir()
        let bundles = try (0..<24).map { try Fixture.logicx(in: dir, name: "p\($0).logicx") }
        let inFlight = Box((now: 0, peak: 0))

        await LibraryScanner.scan(bundles: bundles, workers: 3, parse: { url in
            inFlight.with { $0.now += 1; $0.peak = max($0.peak, $0.now) }
            Thread.sleep(forTimeInterval: 0.02)
            inFlight.with { $0.now -= 1 }
            return try ProjectParser.parse(bundle: url)
        }, onOutcome: { _ in })

        let peak = inFlight.with { $0.peak }
        XCTAssertLessThanOrEqual(peak, 3)
        XCTAssertGreaterThan(peak, 1, "scan ran serially")
    }

    func testParseFailureBecomesFailedOutcomeAndScanContinues() async throws {
        let dir = try Fixture.tempDir()
        let good = try Fixture.logicx(in: dir, name: "good.logicx")
        let bad = dir.appendingPathComponent("bad.logicx")
        try FileManager.default.createDirectory(at: bad, withIntermediateDirectories: true)
        let outcomes = Box<[ScanOutcome]>([])

        await LibraryScanner.scan(bundles: [bad, good], workers: 2) { o in outcomes.with { $0.append(o) } }

        let all = outcomes.with { $0 }
        XCTAssertEqual(all.count, 2)
        XCTAssertTrue(all.contains { if case .failed(let p, _) = $0 { return p == bad.path } else { return false } })
        XCTAssertTrue(all.contains { if case .parsed(let s) = $0 { return s.path == good.path } else { return false } })
    }

    private func stamp(of bundle: URL) throws -> DatabaseStamp {
        let s = try XCTUnwrap(ProjectParser.projectDataStat(bundle: bundle))
        return DatabaseStamp(mtime: s.mtime, size: s.size)
    }

    func testMatchingStampSkipsParsing() async throws {
        let dir = try Fixture.tempDir()
        let bundle = try Fixture.logicx(in: dir, name: "cached.logicx")
        let known = [bundle.path: try stamp(of: bundle)]
        let parseCalls = Box(0)
        let outcome = Box<ScanOutcome?>(nil)

        await LibraryScanner.scan(bundles: [bundle], workers: 2, known: known, parse: { url in
            parseCalls.with { $0 += 1 }
            return try ProjectParser.parse(bundle: url)
        }, onOutcome: { o in outcome.with { $0 = o } })

        XCTAssertEqual(parseCalls.with { $0 }, 0)
        XCTAssertEqual(outcome.with { $0 }, .unchanged(path: bundle.path))
    }

    func testChangedStampIsReparsed() async throws {
        let dir = try Fixture.tempDir()
        let bundle = try Fixture.logicx(in: dir, name: "stale.logicx")
        var old = try stamp(of: bundle)
        old.size += 1 // ProjectData has changed since it was stored
        let outcome = Box<ScanOutcome?>(nil)

        await LibraryScanner.scan(bundles: [bundle], workers: 2, known: [bundle.path: old], onOutcome: { o in outcome.with { $0 = o } })

        guard case .parsed(let s)? = outcome.with({ $0 }) else { return XCTFail("expected a re-parse, got \(String(describing: outcome.with { $0 }))") }
        XCTAssertEqual(s.projectDataSize, old.size - 1)
    }

    func testChangedMTimeAloneIsAlsoReparsed() async throws {
        let dir = try Fixture.tempDir()
        let bundle = try Fixture.logicx(in: dir, name: "touched.logicx")
        var old = try stamp(of: bundle)
        old.mtime -= 60
        let outcome = Box<ScanOutcome?>(nil)

        await LibraryScanner.scan(bundles: [bundle], workers: 1, known: [bundle.path: old], onOutcome: { o in outcome.with { $0 = o } })

        guard case .parsed? = outcome.with({ $0 }) else { return XCTFail("expected a re-parse") }
    }

    func testUnknownBundleIsParsedAndUnparseableStaysFailedEvenWithStamp() async throws {
        let dir = try Fixture.tempDir()
        let fresh = try Fixture.logicx(in: dir, name: "fresh.logicx")
        let broken = dir.appendingPathComponent("broken.logicx")
        try FileManager.default.createDirectory(at: broken, withIntermediateDirectories: true)
        let outcomes = Box<[ScanOutcome]>([])

        await LibraryScanner.scan(bundles: [fresh, broken], workers: 2, known: [broken.path: DatabaseStamp(mtime: 1, size: 1)]) { o in outcomes.with { $0.append(o) } }

        let all = outcomes.with { $0 }
        XCTAssertTrue(all.contains { if case .parsed(let s) = $0 { return s.path == fresh.path } else { return false } })
        XCTAssertTrue(all.contains { if case .failed(let p, _) = $0 { return p == broken.path } else { return false } })
    }

    func testChangedBundlesAreNewOnesAndThoseWithADifferentStamp() async throws {
        let dir = try Fixture.tempDir()
        let same = try Fixture.logicx(in: dir, name: "same.logicx"), edited = try Fixture.logicx(in: dir, name: "edited.logicx")
        let fresh = try Fixture.logicx(in: dir, name: "fresh.logicx"), gone = dir.appendingPathComponent("gone.logicx")
        func stamp(_ u: URL) -> DatabaseStamp {
            let st = ProjectParser.projectDataStat(bundle: u)!
            return DatabaseStamp(mtime: st.mtime, size: st.size)
        }
        var editedStamp = stamp(edited); editedStamp.size += 1
        let known = [same.path: stamp(same), edited.path: editedStamp]

        let changed = await LibraryScanner.changedBundles([same, edited, fresh, gone], known: known, workers: 3)

        XCTAssertEqual(changed.map(\.lastPathComponent), ["edited.logicx", "fresh.logicx", "gone.logicx"], "order kept; a bundle without ProjectData is left to the parser to report")
    }

    func testNothingChangedMeansNothingToParse() async throws {
        let dir = try Fixture.tempDir()
        let bundles = try (0..<10).map { try Fixture.logicx(in: dir, name: "p\($0).logicx") }
        var known: [String: DatabaseStamp] = [:]
        for b in bundles { let st = ProjectParser.projectDataStat(bundle: b)!; known[b.path] = DatabaseStamp(mtime: st.mtime, size: st.size) }
        let changed = await LibraryScanner.changedBundles(bundles, known: known, workers: 4)
        XCTAssertTrue(changed.isEmpty)
    }
}
