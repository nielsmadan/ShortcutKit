import AppKit
import Carbon.HIToolbox
@testable import ShortcutKit
import Testing

enum SeqAction: String, ShortcutAction {
    case save, openProject, closeProject
    var definition: ShortcutActionDefinition {
        switch self {
        case .save: .init("Save", "cmd+s")
        case .openProject: .init("Open Project", "cmd+k cmd+o")
        case .closeProject: .init("Close Project", "cmd+k cmd+w")
        }
    }
}

@MainActor
@Suite("ContextMatcher") struct ContextMatcherTests {
    private func keyDown(_ keyCode: Int, _ modifiers: NSEvent.ModifierFlags) -> NSEvent {
        let cg = CGEvent(keyboardEventSource: nil,
                         virtualKey: CGKeyCode(keyCode), keyDown: true)!
        cg.flags = CGEventFlags(rawValue: UInt64(modifiers.rawValue))
        return NSEvent(cgEvent: cg)!
    }

    @Test("a discrete match dispatches the action with .discrete")
    func discreteMatchDispatches() {
        var fired: (SeqAction, ShortcutDispatch)?
        let ctx = ShortcutContext<SeqAction>("editor") { action, kind in
            fired = (action, kind)
        }
        let matcher = ContextMatcher(context: ctx)
        let result = matcher.handle(keyDown(kVK_ANSI_S, .command))
        #expect(result == .fired)
        #expect(fired?.0 == .save)
        #expect(fired?.1 == .discrete)
    }

    @Test("a non-matching event returns .ignored and does not dispatch")
    func nonMatchingIgnored() {
        var fired = false
        let ctx = ShortcutContext<SeqAction>("editor") { _, _ in fired = true }
        let matcher = ContextMatcher(context: ctx)
        let result = matcher.handle(keyDown(kVK_ANSI_X, .command))
        #expect(result == .ignored)
        #expect(fired == false)
    }

    @Test("prefix-sharing sequences advance in parallel then one fires")
    func prefixSharingAdvancesThenFires() {
        var fired: SeqAction?
        let ctx = ShortcutContext<SeqAction>("editor") { action, _ in fired = action }
        let matcher = ContextMatcher(context: ctx)

        let advance = matcher.handle(keyDown(kVK_ANSI_K, .command))
        if case .advanced = advance {} else { Issue.record("expected .advanced") }
        #expect(fired == nil)

        let fire = matcher.handle(keyDown(kVK_ANSI_O, .command))
        #expect(fire == .fired)
        #expect(fired == .openProject)
    }

    @Test("after one sibling fires, the other resets so its prefix advance is gone")
    func siblingResetAfterFire() {
        var firedSequence: [SeqAction] = []
        let ctx = ShortcutContext<SeqAction>("editor") { action, _ in
            firedSequence.append(action)
        }
        let matcher = ContextMatcher(context: ctx)

        _ = matcher.handle(keyDown(kVK_ANSI_K, .command))
        _ = matcher.handle(keyDown(kVK_ANSI_O, .command))

        let result = matcher.handle(keyDown(kVK_ANSI_W, .command))
        #expect(result == .ignored)
        #expect(firedSequence == [.openProject])
    }

    @Test("reset() returns all matchers to step 0")
    func resetReturnsToStartingState() {
        let ctx = ShortcutContext<SeqAction>("editor") { _, _ in }
        let matcher = ContextMatcher(context: ctx)
        _ = matcher.handle(keyDown(kVK_ANSI_K, .command))
        matcher.reset()
        #expect(matcher.handle(keyDown(kVK_ANSI_O, .command)) == .ignored)
    }
}
