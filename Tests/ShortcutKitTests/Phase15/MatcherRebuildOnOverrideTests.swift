import AppKit
import Carbon.HIToolbox
import ShortcutField
@testable import ShortcutKit
import Testing

@MainActor
@Suite("MatcherRebuildOnOverride") struct MatcherRebuildOnOverrideTests {
    enum Act: String, ShortcutAction {
        case save
        var definition: ShortcutActionDefinition { .init("Save", Shortcut("cmd+s")) }
    }

    private func keyDown(_ keyCode: Int, _ modifiers: NSEvent.ModifierFlags) -> NSEvent {
        let cg = CGEvent(keyboardEventSource: nil,
                         virtualKey: CGKeyCode(keyCode), keyDown: true)!
        cg.flags = CGEventFlags(rawValue: UInt64(modifiers.rawValue))
        return NSEvent(cgEvent: cg)!
    }

    // Runtime overrides must rebuild the live matcher, not only persisted state.
    @Test("override change rebuilds matcher")
    func overrideRebuildsMatcher() throws {
        var fired = 0
        let ctx = ShortcutContext<Act>("editor")
        ctx.__setActiveHandler { action, _ in
            if action == .save { fired += 1 }
        }
        let registry = ShortcutRegistry(contexts: [ctx])

        ctx.setShortcuts([Shortcut("opt+s")], for: .save)

        guard let matcher = registry.matchers[ctx.id] else {
            Issue.record("expected matcher attached for context")
            return
        }

        _ = matcher.handle(keyDown(kVK_ANSI_S, .command))
        #expect(fired == 0)

        _ = matcher.handle(keyDown(kVK_ANSI_S, .option))
        #expect(fired == 1)
    }
}
