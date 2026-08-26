import AppKit
import ShortcutField

/// What became of one key event, for debugging why a shortcut did or didn't fire.
///
/// Emitted on ``ShortcutRegistry/debugEvents`` while
/// ``ShortcutRegistry/isDebugRecording`` is `true`. The registry stores nothing —
/// keep whatever history you need on the observing side.
public struct ShortcutDebugEvent: Sendable, Hashable {
    public enum Outcome: Sendable, Hashable {
        /// An action ran. `stackDepth` is the winning matcher's distance from the
        /// innermost activation: `0` is innermost — the one that wins ties.
        case dispatched(ActionRef, stackDepth: Int)
        /// A chord step was consumed; the sequence is mid-flight.
        case advanced(ActionRef)
        /// Matched, but the action set `allowsKeyRepeat: false` and this was a
        /// key repeat. The event is still consumed.
        case suppressedKeyRepeat(ActionRef)
        /// Nothing matched.
        ///
        /// Also covers keystrokes surrendered to a focused text field:
        /// ShortcutField's focus gate returns the same result as a non-match, so
        /// the two cannot be told apart from here.
        case noMatch
    }

    /// The keystroke as a single-step shortcut, for a layout-aware
    /// `displayString` without carrying a non-`Sendable` `NSEvent`.
    public let pressed: DiscreteShortcut
    public let outcome: Outcome

    public init(pressed: DiscreteShortcut, outcome: Outcome) {
        self.pressed = pressed
        self.outcome = outcome
    }
}

extension ShortcutDebugEvent {
    /// Builds the pressed-key representation. Key events only — `keyCode` traps
    /// on scroll and gesture events.
    static func pressedShortcut(from event: NSEvent) -> DiscreteShortcut? {
        guard event.type == .keyDown else { return nil }
        return DiscreteShortcut(keyCode: event.keyCode, modifiers: event.modifierFlags)
    }
}
