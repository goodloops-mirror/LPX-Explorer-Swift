import XCTest
@testable import LpxCore

final class PlaybackShortcutTests: XCTestCase {
    private func toggles(key: UInt16 = PlaybackShortcut.spaceKeyCode, modifiers: Bool = false, editing: Bool = false, active: Bool = true) -> Bool {
        PlaybackShortcut.shouldToggle(keyCode: key, hasModifiers: modifiers, isEditingText: editing, playerActive: active)
    }

    func testSpaceTogglesWhenSomethingIsLoaded() { XCTAssertTrue(toggles()) }
    func testNotWhileTypingInATextField() { XCTAssertFalse(toggles(editing: true)) }
    func testNothingToPlayMeansTheKeyIsLeftAlone() { XCTAssertFalse(toggles(active: false)) }
    func testOtherKeysAreIgnored() { XCTAssertFalse(toggles(key: 0)); XCTAssertFalse(toggles(key: 36)) }
    func testShortcutsWithModifiersAreIgnored() { XCTAssertFalse(toggles(modifiers: true)) }
}
