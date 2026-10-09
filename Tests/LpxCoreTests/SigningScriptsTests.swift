import XCTest

/// Developer ID signing and notarization are driven by scripts/sign-app.sh (used by package.sh / release.sh when the
/// signing identity is configured). These tests only dry-run it: nothing is signed, uploaded or written.
final class SigningScriptsTests: XCTestCase {
    private var root: URL { URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent() }

    private func run(_ args: [String], env: [String: String] = [:]) throws -> (status: Int32, out: String) {
        let p = Process()
        p.executableURL = root.appendingPathComponent("scripts/sign-app.sh")
        p.arguments = args
        var environment = ProcessInfo.processInfo.environment
        environment["LPX_SIGN_IDENTITY"] = nil; environment["LPX_NOTARY_PROFILE"] = nil
        for (k, v) in env { environment[k] = v }
        p.environment = environment
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = pipe
        try p.run(); p.waitUntilExit()
        return (p.terminationStatus, String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self))
    }

    func testSigningNeedsAnIdentityAndSaysHowToSetOne() throws {
        let r = try run(["--dry-run"])
        XCTAssertNotEqual(r.status, 0)
        XCTAssertTrue(r.out.contains("LPX_SIGN_IDENTITY"), r.out)
    }

    func testDryRunSignsWithTheHardenedRuntimeAndATimestamp() throws {
        let r = try run(["--dry-run"], env: ["LPX_SIGN_IDENTITY": "Developer ID Application: Test (ABCDE12345)"])
        XCTAssertEqual(r.status, 0, r.out)
        XCTAssertTrue(r.out.contains("codesign"))
        XCTAssertTrue(r.out.contains("--options runtime"), "hardened runtime is required for notarization")
        XCTAssertTrue(r.out.contains("--timestamp"), "a secure timestamp is required for notarization")
        XCTAssertTrue(r.out.contains("Developer ID Application: Test (ABCDE12345)"))
        XCTAssertTrue(r.out.contains("entitlements.plist"))
        XCTAssertFalse(r.out.contains("notarytool"), "notarizing is opt-in")
    }

    func testNotarizeSubmitsWaitsAndStaples() throws {
        let r = try run(["--dry-run", "--notarize"], env: ["LPX_SIGN_IDENTITY": "ID", "LPX_NOTARY_PROFILE": "lpx-notary"])
        XCTAssertEqual(r.status, 0, r.out)
        XCTAssertTrue(r.out.contains("notarytool submit"))
        XCTAssertTrue(r.out.contains("--keychain-profile lpx-notary"))
        XCTAssertTrue(r.out.contains("--wait"))
        XCTAssertTrue(r.out.contains("stapler staple"))
        // Order: sign, then notarize, then staple.
        let sign = r.out.range(of: "codesign")!.lowerBound, notarize = r.out.range(of: "notarytool submit")!.lowerBound, staple = r.out.range(of: "stapler staple")!.lowerBound
        XCTAssertTrue(sign < notarize && notarize < staple)
    }

    func testNotarizeNeedsAKeychainProfile() throws {
        let r = try run(["--dry-run", "--notarize"], env: ["LPX_SIGN_IDENTITY": "ID"])
        XCTAssertNotEqual(r.status, 0)
        XCTAssertTrue(r.out.contains("LPX_NOTARY_PROFILE"), r.out)
    }

    func testTheEntitlementsFileIsAValidPlist() throws {
        let data = try Data(contentsOf: root.appendingPathComponent("scripts/entitlements.plist"))
        XCTAssertNoThrow(try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any])
    }

    func testPackagingSignsWhenAnIdentityIsConfigured() throws {
        let package = try String(contentsOf: root.appendingPathComponent("scripts/package.sh"), encoding: .utf8)
        XCTAssertTrue(package.contains("LPX_SIGN_IDENTITY"))
        XCTAssertTrue(package.contains("sign-app.sh"))
        let make = try String(contentsOf: root.appendingPathComponent("scripts/make-app.sh"), encoding: .utf8)
        XCTAssertTrue(make.contains("LPX_BUNDLE_ID"), "the bundle identifier can be set for release builds")
    }

    func testTheSigningGuideExistsAndNamesTheSteps() throws {
        let doc = try String(contentsOf: root.appendingPathComponent("docs/SIGNING.md"), encoding: .utf8)
        for word in ["store-credentials", "LPX_SIGN_IDENTITY", "LPX_NOTARY_PROFILE", "spctl"] { XCTAssertTrue(doc.contains(word), word) }
    }
}
