import AppKit
import LpxCore

/// Space bar = play / pause for the player, unless the user is typing in a text field (see `PlaybackShortcut`).
/// A local key monitor, so it works wherever the focus is inside the app's windows.
@MainActor
final class SpaceBarPlayback {
    private var monitor: Any?

    func install(player: AudioPlayerModel) {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let editing = (NSApp.keyWindow?.firstResponder).map { $0 is NSText || $0 is NSTextField || $0 is NSTextView } ?? false
            let modifiers = !event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty
            let toggle = MainActor.assumeIsolated {
                PlaybackShortcut.shouldToggle(keyCode: event.keyCode, hasModifiers: modifiers, isEditingText: editing, playerActive: player.isActive)
            }
            guard toggle else { return event }
            MainActor.assumeIsolated { player.togglePlayPause() }
            return nil   // consumed: the key does nothing else
        }
    }
}
