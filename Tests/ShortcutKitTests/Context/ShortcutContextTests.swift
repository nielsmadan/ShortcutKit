import Combine
@testable import ShortcutKit
import Testing

enum EditorAction: String, ShortcutAction {
    case save, quit
    var definition: ShortcutActionDefinition {
        switch self {
        case .save: .init("Save", "cmd+s")
        case .quit: .init("Quit")
        }
    }
}

@MainActor
@Suite("ShortcutContext") struct ShortcutContextTests {
    @Test("dispatch invokes the closure with .discrete")
    func dispatchCallsClosureDiscrete() {
        var captured: (EditorAction, ShortcutDispatch)?
        let ctx = ShortcutContext<EditorAction>("editor") { action, kind in
            captured = (action, kind)
        }
        ctx.dispatch(.save)
        #expect(captured?.0 == .save)
        #expect(captured?.1 == .discrete)
    }

    @Test("notify does not invoke the closure")
    func notifyDoesNotCallClosure() {
        var called = false
        let ctx = ShortcutContext<EditorAction>("editor") { _, _ in called = true }
        ctx.notify(.save)
        #expect(called == false)
    }

    @Test("shortcut(for:) falls back to definition default")
    func shortcutFallsBackToDefault() {
        let ctx = ShortcutContext<EditorAction>("editor") { _, _ in }
        let saveExpected: Shortcut = "cmd+s"
        #expect(ctx.shortcut(for: .save) == saveExpected)
        #expect(ctx.shortcut(for: .quit) == nil)
    }

    @Test("displayString(for:) reflects the effective shortcut")
    func displayStringFromShortcut() {
        let ctx = ShortcutContext<EditorAction>("editor") { _, _ in }
        #expect(ctx.displayString(for: .save) == "⌘s")
        #expect(ctx.displayString(for: .quit) == nil)
    }

    @Test("isCustomized is false with no registry attached")
    func isCustomizedFalseStandalone() {
        let ctx = ShortcutContext<EditorAction>("editor") { _, _ in }
        #expect(ctx.isCustomized(.save) == false)
    }

    @Test("shortcutChanges(for:) emits the current effective value on subscribe")
    func shortcutChangesEmitsCurrent() {
        let ctx = ShortcutContext<EditorAction>("editor") { _, _ in }
        var received: Shortcut??
        let cancellable = ctx.shortcutChanges(for: .save).sink { received = $0 }
        let expected: Shortcut = "cmd+s"
        #expect(received == .some(.some(expected)))
        _ = cancellable
    }
}
