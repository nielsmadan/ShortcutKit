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

    /// Overriding the binding at runtime must rebuild the live matcher so the
    /// new shortcut fires and the old one stops matching. Pre-fix, the matcher
    /// was frozen at registry-init time and overrides only affected persistence
    /// and the headless table — a real bug surfaced via the sensitivity slider
    /// in the example app's continuous-rotate row.
    @Test("override change rebuilds matcher")
    func overrideRebuildsMatcher() throws {
        var fired = 0
        let ctx = ShortcutContext<Act>("editor") { action, _ in
            if action == .save { fired += 1 }
        }
        let registry = ShortcutRegistry(contexts: [ctx])

        registry.setShortcuts([Shortcut("opt+s")], for: .save, in: ctx)

        guard let matcher = registry.matchers[ctx.id] else {
            Issue.record("expected matcher attached for context")
            return
        }

        // Old default no longer matches.
        _ = matcher.handle(keyDown(kVK_ANSI_S, .command))
        #expect(fired == 0)

        // New override fires.
        _ = matcher.handle(keyDown(kVK_ANSI_S, .option))
        #expect(fired == 1)
    }
}
