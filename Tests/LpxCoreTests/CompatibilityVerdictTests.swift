import XCTest
@testable import LpxCore

final class CompatibilityVerdictTests: XCTestCase {
    private func au(_ type: String, _ sub: String, _ mfr: String, name: String? = nil) -> AURef {
        AURef(typeCode: type, subtype: sub, manufacturer: mfr, offset: 0, displayName: name)
    }
    private let a = AURef(typeCode: "aufx", subtype: "AAAA", manufacturer: "Mfr1", offset: 0)
    private let b = AURef(typeCode: "aumu", subtype: "BBBB", manufacturer: "Mfr2", offset: 0)
    private let c = AURef(typeCode: "aufx", subtype: "CCC ", manufacturer: "kHs ", offset: 0)

    func testUnknownWhenRegistryNotRead() {
        let v = CompatibilityVerdict.evaluate(plugins: [a], installed: nil)
        XCTAssertEqual(v.status, .unknown)
        XCTAssertEqual(v.headline, "Haven't checked your AUs yet")
        XCTAssertNil(v.summary)
        XCTAssertTrue(v.missing.isEmpty)
    }

    func testCleanWhenEveryPluginInstalled() {
        let v = CompatibilityVerdict.evaluate(plugins: [a, b], installed: [a.fingerprint, b.fingerprint, "extra/xxxx/yyyy"])
        XCTAssertEqual(v.status, .clean)
        XCTAssertEqual(v.headline, "Opens cleanly")
        XCTAssertEqual(v.summary, "All 2 plug-ins installed on this Mac.")
        XCTAssertEqual(v.total, 2)
    }

    func testSingularWording() {
        XCTAssertEqual(CompatibilityVerdict.evaluate(plugins: [a], installed: [a.fingerprint]).summary, "All 1 plug-in installed on this Mac.")
        let v = CompatibilityVerdict.evaluate(plugins: [a, b], installed: [b.fingerprint])
        XCTAssertEqual(v.headline, "1 plug-in missing")
    }

    func testWarningsWhenSomeMissing() {
        let v = CompatibilityVerdict.evaluate(plugins: [a, b, c], installed: [a.fingerprint])
        XCTAssertEqual(v.status, .warnings)
        XCTAssertEqual(v.headline, "2 plug-ins missing")
        XCTAssertEqual(v.summary, "2 of 3 plug-ins not installed on this Mac.")
        XCTAssertEqual(v.missing.map(\.fingerprint), [b.fingerprint, c.fingerprint])
    }

    func testWillNotOpenWhenAllMissing() {
        let v = CompatibilityVerdict.evaluate(plugins: [a, b], installed: [])
        XCTAssertEqual(v.status, .willNotOpen)
        XCTAssertEqual(v.headline, "Will not open")
        XCTAssertEqual(v.summary, "2 of 2 plug-ins missing on this Mac.")
    }

    func testNoPluginsIsClean() {
        let v = CompatibilityVerdict.evaluate(plugins: [], installed: [])
        XCTAssertEqual(v.status, .clean)
        XCTAssertEqual(v.summary, "No plug-ins to check.")
    }

    func testAppleStockPluginsCountAsInstalledEvenIfNotInAuval() {
        let stock = au("aufx", "limi", "appl", name: "Limiter")
        let v = CompatibilityVerdict.evaluate(plugins: [stock, a], installed: [a.fingerprint])
        XCTAssertEqual(v.status, .clean)
        XCTAssertTrue(v.missing.isEmpty)
    }

    func testRepeatedInstancesCountOnceAndFingerprintsKeepSpaces() {
        let v = CompatibilityVerdict.evaluate(plugins: [a, a, a, c, c], installed: [a.fingerprint])
        XCTAssertEqual(v.total, 2, "unique plug-ins, not instances")
        XCTAssertEqual(v.missing.count, 1)
        XCTAssertEqual(v.headline, "1 plug-in missing")
        // 4CCs with significant spaces must match verbatim
        XCTAssertEqual(CompatibilityVerdict.evaluate(plugins: [c], installed: ["aufx/CCC /kHs "]).status, .clean)
        XCTAssertEqual(CompatibilityVerdict.evaluate(plugins: [c], installed: ["aufx/CCC/kHs"]).status, .willNotOpen)
    }

    func testStockOnlyProjectWithUnknownRegistryStaysUnknown() {
        XCTAssertEqual(CompatibilityVerdict.evaluate(plugins: [au("aufx", "limi", "appl", name: "Limiter")], installed: nil).status, .unknown)
    }
}
