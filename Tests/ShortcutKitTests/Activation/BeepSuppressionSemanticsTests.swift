import AppKit
import Carbon.HIToolbox
import ShortcutField
@testable import ShortcutKit
import Testing

/// Pins the beep-suppression contract wired up in `ShortcutRegistry.init`.
///
/// A press beeps when the event reaches the responder chain (nobody consumed it)
/// and the suppressor does not squelch it (`ShortcutTracking.isActive` false).
/// For a single matcher that reduces to: **beeps exactly when the result is
/// `.ignored`** — `.fired` consumes the event, `.advanced` sets tracking.
/// Serialized because `ShortcutTracking` is process-wide state.
@MainActor
@Suite("BeepSuppressionSemantics", .serialized) struct BeepSuppressionSemanticsTests {
    private func keyDown(_ keyCode: Int, _ modifiers: NSEvent.ModifierFlags) -> NSEvent {
        let cg = CGEvent(keyboardEventSource: nil,
                         virtualKey: CGKeyCode(keyCode), keyDown: true)!
        cg.flags = CGEventFlags(rawValue: UInt64(modifiers.rawValue))
        return NSEvent(cgEvent: cg)!
    }

    private func beeps(_ result: ShortcutMatchResult) -> Bool {
        if case .ignored = result { return true }
        return false
    }

    // SeqAction: .save = "cmd+s", .openProject = "cmd+k cmd+o", .closeProject = "cmd+k cmd+w"
    private func makeMatcher() -> ContextMatcher<SeqAction> {
        let ctx = ShortcutContext<SeqAction>("editor")
        ctx.__setActiveHandler { _, _ in }
        return ContextMatcher(context: ctx)
    }

    @Test("an unbound key beeps when no chord is in flight")
    func unboundKeyBeeps() {
        let matcher = makeMatcher()
        #expect(beeps(matcher.handle(keyDown(kVK_ANSI_J, .command))))
        matcher.reset()
    }

    @Test("a chord prefix does not beep and does set tracking")
    func prefixSuppressed() {
        let matcher = makeMatcher()
        let result = matcher.handle(keyDown(kVK_ANSI_K, .command))
        #expect(beeps(result) == false)
        // The prefix event is NOT consumed, so suppression is what silences it.
        #expect(result == .advanced(consumeEvent: false))
        #expect(ShortcutTracking.isActive)
        matcher.reset()
    }

    @Test("a completed chord does not beep — the event is consumed")
    func completionConsumed() {
        let matcher = makeMatcher()
        _ = matcher.handle(keyDown(kVK_ANSI_K, .command))
        let result = matcher.handle(keyDown(kVK_ANSI_O, .command))
        #expect(result == .fired)
        #expect(beeps(result) == false)
        matcher.reset()
    }

    @Test("an invalid second key still beeps — tracking resets before the event lands")
    func invalidSecondKeyBeeps() {
        let matcher = makeMatcher()
        #expect(beeps(matcher.handle(keyDown(kVK_ANSI_K, .command))) == false)
        let result = matcher.handle(keyDown(kVK_ANSI_Z, .command))
        #expect(beeps(result))
        #expect(ShortcutTracking.isActive == false)
        matcher.reset()
    }

    @Test("a plain single-step shortcut never sets tracking")
    func singleStepNeverTracks() {
        let matcher = makeMatcher()
        let result = matcher.handle(keyDown(kVK_ANSI_S, .command))
        #expect(result == .fired)
        #expect(ShortcutTracking.isActive == false)
        matcher.reset()
    }

    @Test("beeping resumes normally after a chord sequence")
    func noStuckSuppression() {
        let matcher = makeMatcher()
        _ = matcher.handle(keyDown(kVK_ANSI_K, .command))
        _ = matcher.handle(keyDown(kVK_ANSI_O, .command))
        #expect(beeps(matcher.handle(keyDown(kVK_ANSI_J, .command))))
        #expect(ShortcutTracking.isActive == false)
        matcher.reset()
    }
}
