import XCTest
@testable import LpxCore

final class SearchMatcherTests: XCTestCase {
    private let doc = SearchDocument(
        projectName: "Summer Anthem v02",
        pluginNames: ["Channel EQ", "Phase Plant"],
        trackNames: ["Kick", "Lead Vox", "Bass Café"])

    func testEmptyQueryMatchesEverything() {
        XCTAssertTrue(SearchMatcher.matches(doc, query: ""))
        XCTAssertTrue(SearchMatcher.matches(doc, query: "   "))
    }

    func testMatchesProjectNameCaseInsensitively() {
        XCTAssertTrue(SearchMatcher.matches(doc, query: "anthem"))
    }

    func testMatchesTrackName() {
        XCTAssertTrue(SearchMatcher.matches(doc, query: "lead vox"))
    }

    func testMatchesPluginName() {
        XCTAssertTrue(SearchMatcher.matches(doc, query: "phase plant"))
    }

    func testAllTermsMustMatchButMayComeFromDifferentFields() {
        XCTAssertTrue(SearchMatcher.matches(doc, query: "summer kick"))
        XCTAssertFalse(SearchMatcher.matches(doc, query: "summer snare"))
    }

    func testDiacriticInsensitive() {
        XCTAssertTrue(SearchMatcher.matches(doc, query: "cafe"))
    }

    func testNoMatch() {
        XCTAssertFalse(SearchMatcher.matches(doc, query: "reverb"))
    }

    func testMatchesAlternativeName() {
        let withAlts = SearchDocument(projectName: "Song", alternativeNames: ["Song", "Radio Edit"])
        XCTAssertTrue(SearchMatcher.matches(withAlts, query: "radio edit"))
        XCTAssertFalse(SearchMatcher.matches(withAlts, query: "club"))
    }

    // MARK: byte-level substring search edge cases (haystacks are folded UTF-8)

    func testSubstringSearchHandlesUnicodeEmojiAndOverlaps() {
        func hit(_ hay: String, _ term: String) -> Bool { SearchMatcher.matches(haystack: SearchMatcher.fold(hay), terms: [SearchMatcher.fold(term)]) }
        XCTAssertTrue(hit("Song 日本語 Mix ☕️ final", "日本語"))
        XCTAssertTrue(hit("Song 日本語 Mix ☕️ final", "☕️"))
        XCTAssertTrue(hit("aaab", "aab"), "needle overlapping its own prefix")
        XCTAssertTrue(hit("abcabcabd", "abcabd"))
        XCTAssertFalse(hit("abcab", "abcabd"), "needle longer than what is left")
        XCTAssertTrue(hit("x", "x"))
        XCTAssertFalse(hit("", "x"))
        XCTAssertTrue(hit("Zoë's Café", "zoe's cafe"))
        XCTAssertFalse(hit("日本語", "日本人"))
    }

    func testEmptyTermListMatchesAndEmptyTermIsIgnored() {
        XCTAssertTrue(SearchMatcher.matches(haystack: "anything", terms: []))
    }
}
