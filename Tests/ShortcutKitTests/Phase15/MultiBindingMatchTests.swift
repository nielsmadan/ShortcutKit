import AppKit
import Carbon.HIToolbox
import ShortcutField
@testable import ShortcutKit
import Testing

@MainActor
@Suite("MultiBindingMatch") struct MultiBindingMatchTests {
    enum Act: String, ShortcutAction {
        case save
        var definition: ShortcutActionDefinition {
            .init("Save", defaults: [Shortcut("cmd+s"), Shortcut("ctrl+s")])
        }
    }

    private func keyDown(_ keyCode: Int, _ modifiers: NSEvent.ModifierFlags) -> NSEvent {
        let cg = CGEvent(keyboardEventSource: nil,
                         virtualKey: CGKeyCode(keyCode), keyDown: true)!
        cg.flags = CGEventFlags(rawValue: UInt64(modifiers.rawValue))
        return NSEvent(cgEvent: cg)!
    }

    @Test("both default bindings fire dispatch")
    func eitherBindingFires() throws {
        var fired = 0
        let ctx = ShortcutContext<Act>("editor")
        ctx.__setActiveHandler { action, _ in
            if action == .save { fired += 1 }
        }
        let matcher = ContextMatcher(context: ctx)

        let r1 = matcher.handle(keyDown(kVK_ANSI_S, .command))
        #expect(r1 == .fired)

        let r2 = matcher.handle(keyDown(kVK_ANSI_S, .control))
        #expect(r2 == .fired)

        #expect(fired == 2)
    }
}
