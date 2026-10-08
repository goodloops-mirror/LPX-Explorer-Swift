import Foundation

/// When the space bar toggles playback: only while something is loaded in the player, only the bare key, and never while
/// the user is typing in a text field.
public enum PlaybackShortcut {
    public static let spaceKeyCode: UInt16 = 49

    public static func shouldToggle(keyCode: UInt16, hasModifiers: Bool, isEditingText: Bool, playerActive: Bool) -> Bool {
        keyCode == spaceKeyCode && !hasModifiers && !isEditingText && playerActive
    }
}
