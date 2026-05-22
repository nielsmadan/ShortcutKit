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
        let ctx = ShortcutContext<Act>("editor") { _, _ in }
        #expect(ctx.shortcuts(for: .save) == [Shortcut("cmd+s"), Shortcut("ctrl+s")])
        #expect(ctx.shortcut(for: .save) == Shortcut("cmd+s"))
    }

    @Test func overrideArrayWins() throws {
        let ctx = ShortcutContext<Act>("editor") { _, _ in }
        let registry = ShortcutRegistry(contexts: [ctx])
        registry.setShortcuts([Shortcut("opt+s")], for: .save, in: ctx)
        #expect(ctx.shortcuts(for: .save) == [Shortcut("opt+s")])
    }

    @Test func resetAllToDefaults() throws {
        let ctx = ShortcutContext<Act>("editor") { _, _ in }
        let registry = ShortcutRegistry(contexts: [ctx])
        registry.setShortcuts([Shortcut("opt+s")], for: .save, in: ctx)
        ctx.resetAllToDefaults()
        #expect(ctx.shortcuts(for: .save) == [Shortcut("cmd+s"), Shortcut("ctrl+s")])
    }

    @Test func currentOccurrencesIncludesAllBindings() {
        let ctx = ShortcutContext<Act>("editor") { _, _ in }
        // Two defaults -> two occurrences (no overrides set).
        #expect(ctx.__currentOccurrences().count == 2)
    }
}
