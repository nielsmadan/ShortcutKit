import ShortcutField
@testable import ShortcutKit
import Testing

@MainActor
struct MultiBindingLookupTests {
    enum Act: String, ShortcutAction {
        case save
        var definition: ShortcutActionDefinition {
            .init("Save", defaults: [Shortcut("cmd+s"), Shortcut("ctrl+s")])
        }
    }

    @Test func shortcutsReturnsAllDefaults() {
        let ctx = ShortcutContext<Act>("editor")
        #expect(ctx.shortcuts(for: .save) == [Shortcut("cmd+s"), Shortcut("ctrl+s")])
        #expect(ctx.shortcuts(for: .save).first == Shortcut("cmd+s"))
    }

    @Test func overrideArrayWins() throws {
        let ctx = ShortcutContext<Act>("editor")
        let registry = ShortcutRegistry(contexts: [ctx])
        ctx.setShortcuts([Shortcut("opt+s")], for: .save)
        #expect(ctx.shortcuts(for: .save) == [Shortcut("opt+s")])
    }

    @Test func resetAllToDefaults() throws {
        let ctx = ShortcutContext<Act>("editor")
        let registry = ShortcutRegistry(contexts: [ctx])
        ctx.setShortcuts([Shortcut("opt+s")], for: .save)
        ctx.resetAll()
        #expect(ctx.shortcuts(for: .save) == [Shortcut("cmd+s"), Shortcut("ctrl+s")])
    }

    @Test func currentOccurrencesIncludesAllBindings() {
        let ctx = ShortcutContext<Act>("editor")
        // Two defaults -> two occurrences (no overrides set).
        #expect(ctx.__currentOccurrences().count == 2)
    }
}
