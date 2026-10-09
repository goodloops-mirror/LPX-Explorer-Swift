import XCTest

/// Releases are distributed as a DMG: the app plus an Applications shortcut to drag it onto. scripts/make-dmg.sh builds it,
/// scripts/sign-app.sh signs / notarizes / staples it, scripts/package.sh chains everything. Dry runs only here.
final class DmgScriptsTests: XCTestCase {
    private var root: URL { URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent() }

    private func run(_ script: String, _ args: [String], env: [String: String] = [:]) throws -> (status: Int32, out: String) {
        let p = Process()
        p.executableURL = root.appendingPathComponent("scripts/\(script)")
        p.arguments = args
        var environment = ProcessInfo.processInfo.environment
        environment["LPX_SIGN_IDENTITY"] = nil; environment["LPX_NOTARY_PROFILE"] = nil
        for (k, v) in env { environment[k] = v }
        p.environment = environment
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = pipe
        try p.run(); p.waitUntilExit()
        return (p.terminationStatus, String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self))
    }

    // MARK: building the image

    func testDryRunBuildsACompressedImageWithTheAppAndAnApplicationsShortcut() throws {
        let r = try run("make-dmg.sh", ["--dry-run", "build/LPX Explorer.app", "dist/Test.dmg"])
        XCTAssertEqual(r.status, 0, r.out)
        XCTAssertTrue(r.out.contains("hdiutil create"), r.out)
        XCTAssertTrue(r.out.contains("-volname LPX Explorer"), "the volume is named after the app")
        XCTAssertTrue(r.out.contains("UDZO"), "compressed, read-only image")
        XCTAssertTrue(r.out.contains("ln -s /Applications"), "drag target")
        XCTAssertTrue(r.out.contains("dist/Test.dmg"))
    }

    func testMakingAnImageNeedsTheAppToExist() throws {
        let r = try run("make-dmg.sh", ["/nonexistent/App.app", "/tmp/never.dmg"])
        XCTAssertNotEqual(r.status, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: "/tmp/never.dmg"))
    }

    // MARK: signing the image

    func testADmgIsSignedWithoutTheHardenedRuntimeThenNotarizedAndStapled() throws {
        let r = try run("sign-app.sh", ["dist/Test.dmg", "--notarize", "--dry-run"], env: ["LPX_SIGN_IDENTITY": "ID", "LPX_NOTARY_PROFILE": "lpx-notary"])
        XCTAssertEqual(r.status, 0, r.out)
        XCTAssertTrue(r.out.contains("codesign --force --timestamp --sign ID dist/Test.dmg"), r.out)
        XCTAssertFalse(r.out.contains("--options runtime"), "that flag is for executables")
        XCTAssertTrue(r.out.contains("notarytool submit dist/Test.dmg"), "an image is submitted as it is, not zipped")
        XCTAssertFalse(r.out.contains("ditto"))
        XCTAssertTrue(r.out.contains("stapler staple dist/Test.dmg"))
        XCTAssertTrue(r.out.contains("--type open"), "Gatekeeper assesses an image as a download")
    }

    // MARK: the whole chain

    func testPackagingBuildsTheImageAndNoLongerAZip() throws {
        let package = try String(contentsOf: root.appendingPathComponent("scripts/package.sh"), encoding: .utf8)
        XCTAssertTrue(package.contains("make-dmg.sh"))
        XCTAssertTrue(package.contains(".dmg"))
        XCTAssertFalse(package.contains("ditto -c -k --keepParent"), "no zip any more")
        // The app is signed (and notarized) before it goes into the image, and the image is signed and notarized after.
        let app = package.range(of: "sign-app.sh\" \"$src/build/LPX Explorer.app\"")?.lowerBound
        let dmg = package.range(of: "make-dmg.sh")?.lowerBound
        let image = package.range(of: "sign-app.sh\" \"$dmgPath\"")?.lowerBound
        guard let app, let dmg, let image else { return XCTFail("package.sh must sign the app, build the image, then sign the image") }
        XCTAssertTrue(app < dmg && dmg < image)
    }

    func testTheDocumentationDescribesTheInstallFromTheImage() throws {
        let readme = try String(contentsOf: root.appendingPathComponent("README.md"), encoding: .utf8)
        XCTAssertTrue(readme.contains(".dmg"))
        XCTAssertFalse(readme.contains("LPX-Explorer-vX.Y.Z.zip"))
        let signing = try String(contentsOf: root.appendingPathComponent("docs/SIGNING.md"), encoding: .utf8)
        XCTAssertTrue(signing.contains("dmg"))
    }
}
