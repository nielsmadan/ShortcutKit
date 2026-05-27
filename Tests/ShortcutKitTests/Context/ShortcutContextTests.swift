import Combine
@testable import ShortcutKit
import Testing

enum EditorAction: String, ShortcutAction {
    case save, quit, pan
    var definition: ShortcutActionDefinition {
        switch self {
        case .save: .init("Save", "cmd+s")
        case .quit: .init("Quit")
        case .pan: .init("Pan", kind: .continuous)
        }
    }
}

@MainActor
@Suite("ShortcutContext") struct ShortcutContextTests {
    @Test("dispatch invokes the closure with .discrete for discrete actions")
    func dispatchCallsClosureDiscrete() {
        var captured: (EditorAction, ShortcutDispatch)?
        let ctx = ShortcutContext<EditorAction>("editor") { action, kind in
            captured = (action, kind)
        }
        ctx.dispatch(.save)
        #expect(captured?.0 == .save)
        #expect(captured?.1 == .discrete)
    }

    @Test("dispatch invokes the closure with .continuous for continuous actions")
    func dispatchCallsClosureContinuous() {
        var captured: ShortcutDispatch?
        let ctx = ShortcutContext<EditorAction>("editor") { _, kind in
            captured = kind
        }
        ctx.dispatch(.pan)
        #expect(captured == .continuous(magnitude: 1.0))
    }

    @Test("notify does not invoke the closure")
    func notifyDoesNotCallClosure() {
        var called = false
        let ctx = ShortcutContext<EditorAction>("editor") { _, _ in called = true }
        ctx.notify(.save)
        #expect(called == false)
    }

    @Test("shortcuts(for:).first falls back to definition default")
    func shortcutFallsBackToDefault() {
        let ctx = ShortcutContext<EditorAction>("editor") { _, _ in }
        let saveExpected: Shortcut = "cmd+s"
        #expect(ctx.shortcuts(for: .save).first == saveExpected)
        #expect(ctx.shortcuts(for: .quit).first == nil)
    }

    @Test("displayStrings(for:).first reflects the effective shortcut")
    func displayStringFromShortcut() {
        let ctx = ShortcutContext<EditorAction>("editor") { _, _ in }
        #expect(ctx.displayStrings(for: .save).first == "⌘s")
        #expect(ctx.displayStrings(for: .quit).first == nil)
    }

    @Test("isCustomized is false with no registry attached")
    func isCustomizedFalseStandalone() {
        let ctx = ShortcutContext<EditorAction>("editor") { _, _ in }
        #expect(ctx.isCustomized(.save) == false)
    }

    @Test("shortcutsChanges(for:) emits the full bindings array on subscribe")
    func shortcutsChangesEmitsCurrent() {
        let ctx = ShortcutContext<EditorAction>("editor") { _, _ in }
        var received: [Shortcut]?
        let cancellable = ctx.shortcutsChanges(for: .save).sink { received = $0 }
        let expected: Shortcut = "cmd+s"
        #expect(received == [expected])
        _ = cancellable
    }

    @Test("displayStrings(for:) returns one entry per binding")
    func displayStringsArray() {
        let ctx = ShortcutContext<EditorAction>("editor") { _, _ in }
        #expect(ctx.displayStrings(for: .save) == ["⌘s"])
        #expect(ctx.displayStrings(for: .quit) == [])
    }
}
