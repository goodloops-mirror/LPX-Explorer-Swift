import XCTest
@testable import LpxCore

final class AboutInfoTests: XCTestCase {
    private func links(_ lines: [AboutInfo.Line]) -> [String: String] {
        var out: [String: String] = [:]
        for l in lines { for s in l.segments { if let link = s.link { out[s.text] = link } } }
        return out
    }
    private func all(_ lines: [AboutInfo.Line]) -> String { lines.map(\.text).joined(separator: "\n") }

    func testBrandingLinksToGoodLoops() {
        let lines = AboutInfo.credits()
        XCTAssertTrue(all(lines).contains("Good Loops"))
        XCTAssertEqual(links(lines)["Good Loops"], "https://www.good-loops.com")
    }

    func testAcknowledgesTheOriginalAuthorAndTheLicence() {
        let text = all(AboutInfo.credits())
        XCTAssertTrue(text.contains("Rhyd Lewis"))
        XCTAssertTrue(text.contains("GPL"))
        XCTAssertTrue(AboutInfo.copyright.contains("Good Loops"))
        XCTAssertTrue(AboutInfo.copyright.contains(AboutInfo.license))
    }

    func testPlaceholdersAreShownUntilTheLinksExist() {
        let lines = AboutInfo.credits(repositoryURL: nil, coffeeURL: nil)
        let text = all(lines)
        XCTAssertTrue(text.contains("Source code") && text.contains("coming soon"))
        XCTAssertTrue(text.contains("Buy me a coffee") && text.contains("coming soon"))
        XCTAssertEqual(Set(links(lines).values), ["https://www.good-loops.com"], "no dead links while the targets don't exist")
    }

    func testLinksAppearOnceTheyAreConfigured() {
        let lines = AboutInfo.credits(repositoryURL: "https://github.com/example/lpx", coffeeURL: "https://buymeacoffee.com/example")
        let l = links(lines)
        XCTAssertEqual(l["GitHub"], "https://github.com/example/lpx")
        XCTAssertEqual(l["Buy me a coffee"], "https://buymeacoffee.com/example")
        XCTAssertFalse(all(lines).contains("coming soon"))
    }
}

final class AboutVersionTextTests: XCTestCase {
    func testExactBuildIsShownWhenItDiffersFromTheRelease() {
        XCTAssertEqual(AboutInfo.versionText(short: "0.4.0", build: "320", describe: "v0.4.0-1-g2f018f0-dirty"),
                       "Version 0.4.0 · build 320 · v0.4.0-1-g2f018f0-dirty")
    }

    func testPlainReleaseDoesNotRepeatItself() {
        XCTAssertEqual(AboutInfo.versionText(short: "0.4.0", build: "320", describe: "v0.4.0"), "Version 0.4.0 · build 320")
    }

    func testMissingPartsAreLeftOut() {
        XCTAssertEqual(AboutInfo.versionText(short: "0.4.0", build: nil, describe: nil), "Version 0.4.0")
        XCTAssertEqual(AboutInfo.versionText(short: nil, build: nil, describe: nil), "Development build")
        XCTAssertEqual(AboutInfo.versionText(short: "", build: "", describe: ""), "Development build")
    }
}
