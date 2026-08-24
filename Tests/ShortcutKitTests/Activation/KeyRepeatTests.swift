import AppKit
import Carbon.HIToolbox
@testable import ShortcutKit
import Testing

enum RepeatAction: String, ShortcutAction {
    case nudge, deleteItem

    var definition: ShortcutActionDefinition {
        switch self {
        case .nudge: .init("Nudge", "cmd+j")
        case .deleteItem: .init("Delete", "cmd+d", allowsKeyRepeat: false)
        }
    }
}

@MainActor
@Suite("Key repeat") struct KeyRepeatTests {
    private func keyDown(_ keyCode: Int, _ modifiers: NSEvent.ModifierFlags, isARepeat: Bool = false) -> NSEvent {
        let cg = CGEvent(keyboardEventSource: nil,
                         virtualKey: CGKeyCode(keyCode), keyDown: true)!
        cg.flags = CGEventFlags(rawValue: UInt64(modifiers.rawValue))
        cg.setIntegerValueField(.keyboardEventAutorepeat, value: isARepeat ? 1 : 0)
        return NSEvent(cgEvent: cg)!
    }

    @Test("an action opting out of key repeat fires once on the initial press")
    func optedOutFiresOnInitialPress() {
        var fired: [RepeatAction] = []
        let ctx = ShortcutContext<RepeatAction>("editor")
        ctx.__setActiveHandler { action, _ in fired.append(action) }
        let matcher = ContextMatcher(context: ctx)

        let result = matcher.handle(keyDown(kVK_ANSI_D, .command))

        #expect(result == .fired)
        #expect(fired == [.deleteItem])
    }

    @Test("a repeat event does not dispatch an action that opted out")
    func optedOutSuppressesRepeat() {
        var fired: [RepeatAction] = []
        let ctx = ShortcutContext<RepeatAction>("editor")
        ctx.__setActiveHandler { action, _ in fired.append(action) }
        let matcher = ContextMatcher(context: ctx)

        _ = matcher.handle(keyDown(kVK_ANSI_D, .command))
        _ = matcher.handle(keyDown(kVK_ANSI_D, .command, isARepeat: true))
        _ = matcher.handle(keyDown(kVK_ANSI_D, .command, isARepeat: true))

        #expect(fired == [.deleteItem])
    }

    @Test("a suppressed repeat still consumes the event")
    func suppressedRepeatStillConsumes() {
        let ctx = ShortcutContext<RepeatAction>("editor")
        ctx.__setActiveHandler { _, _ in }
        let matcher = ContextMatcher(context: ctx)

        _ = matcher.handle(keyDown(kVK_ANSI_D, .command))
        let result = matcher.handle(keyDown(kVK_ANSI_D, .command, isARepeat: true))

        #expect(result == .fired)
    }

    @Test("repeats dispatch normally for an action that allows them")
    func allowedRepeatsDispatch() {
        var fired: [RepeatAction] = []
        let ctx = ShortcutContext<RepeatAction>("editor")
        ctx.__setActiveHandler { action, _ in fired.append(action) }
        let matcher = ContextMatcher(context: ctx)

        _ = matcher.handle(keyDown(kVK_ANSI_J, .command))
        _ = matcher.handle(keyDown(kVK_ANSI_J, .command, isARepeat: true))
        _ = matcher.handle(keyDown(kVK_ANSI_J, .command, isARepeat: true))

        #expect(fired == [.nudge, .nudge, .nudge])
    }

    @Test("allowsKeyRepeat defaults to true")
    func defaultsToAllowingRepeat() {
        #expect(RepeatAction.nudge.definition.allowsKeyRepeat)
        #expect(RepeatAction.deleteItem.definition.allowsKeyRepeat == false)
    }

    /// `NSEvent.isARepeat` throws on non-keyboard events, so the repeat check
    /// must short-circuit on event type before reading it.
    @Test("the repeat check does not read isARepeat on a scroll event")
    func scrollEventDoesNotThrow() {
        let cg = CGEvent(scrollWheelEvent2Source: nil, units: .pixel,
                         wheelCount: 1, wheel1: 10, wheel2: 0, wheel3: 0)!
        let scroll = NSEvent(cgEvent: cg)!

        #expect(ContextMatcher<RepeatAction>.isSuppressedRepeat(scroll, for: .deleteItem) == false)
    }
}
