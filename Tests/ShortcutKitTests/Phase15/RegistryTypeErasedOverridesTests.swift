import ShortcutField
@testable import ShortcutKit
import Testing

@MainActor
struct RegistryTypeErasedOverridesTests {
    enum Act: String, ShortcutAction {
        case save, new
        var definition: ShortcutActionDefinition {
            switch self {
            case .save: .init("Save", Shortcut("cmd+s"))
            case .new: .init("New", Shortcut("cmd+n"))
            }
        }
    }

    @Test func setShortcutsWritesOverride() {
        let ctx = ShortcutContext<Act>("editor")
        let registry = ShortcutRegistry(contexts: [ctx])
        registry.setShortcuts([Shortcut("opt+s")], contextID: "editor", actionID: "save")
        #expect(ctx.shortcuts(for: .save) == [Shortcut("opt+s")])
    }

    @Test func removeShortcutAtIndexRemovesOne() {
        let ctx = ShortcutContext<Act>("editor")
        let registry = ShortcutRegistry(contexts: [ctx])
        registry.setShortcuts(
            [Shortcut("opt+s"), Shortcut("ctrl+s")],
            contextID: "editor",
            actionID: "save"
        )
        registry.removeShortcut(at: 0, contextID: "editor", actionID: "save")
        #expect(ctx.shortcuts(for: .save) == [Shortcut("ctrl+s")])
    }

    @Test func removeShortcutClearsActionWhenEmpty() {
        let ctx = ShortcutContext<Act>("editor")
        let registry = ShortcutRegistry(contexts: [ctx])
        registry.setShortcuts([Shortcut("opt+s")], contextID: "editor", actionID: "save")
        registry.removeShortcut(at: 0, contextID: "editor", actionID: "save")
        // No override -> falls back to default.
        #expect(ctx.shortcuts(for: .save) == [Shortcut("cmd+s")])
    }

    @Test func removeShortcutOutOfRangeIsNoop() {
        let ctx = ShortcutContext<Act>("editor")
        let registry = ShortcutRegistry(contexts: [ctx])
        registry.setShortcuts([Shortcut("opt+s")], contextID: "editor", actionID: "save")
        registry.removeShortcut(at: 99, contextID: "editor", actionID: "save")
        #expect(ctx.shortcuts(for: .save) == [Shortcut("opt+s")])
    }

    @Test func resetActionRestoresDefault() {
        let ctx = ShortcutContext<Act>("editor")
        let registry = ShortcutRegistry(contexts: [ctx])
        registry.setShortcuts([Shortcut("opt+s")], contextID: "editor", actionID: "save")
        registry.reset(contextID: "editor", actionID: "save")
        #expect(ctx.shortcuts(for: .save) == [Shortcut("cmd+s")])
    }

    @Test func resetAllRestoresAllContexts() {
        let ctx1 = ShortcutContext<Act>("editor")
        let ctx2 = ShortcutContext<Act>("browser")
        let registry = ShortcutRegistry(contexts: [ctx1, ctx2])
        registry.setShortcuts([Shortcut("opt+s")], contextID: "editor", actionID: "save")
        registry.setShortcuts([Shortcut("opt+n")], contextID: "browser", actionID: "new")
        registry.resetAll()
        #expect(ctx1.shortcuts(for: .save) == [Shortcut("cmd+s")])
        #expect(ctx2.shortcuts(for: .new) == [Shortcut("cmd+n")])
    }

    enum NoDefaultAct: String, ShortcutAction {
        case run
        var definition: ShortcutActionDefinition { .init("Run", kind: .discrete) }
    }

    @Test func scopeForContextIDFindsContext() {
        let local = ShortcutContext<Act>("editor")
        let global = ShortcutContext<NoDefaultAct>(global: "global") { _, _ in }
        let registry = ShortcutRegistry(contexts: [local, global])
        #expect(registry.scope(forContextID: "editor") == .local)
        #expect(registry.scope(forContextID: "global") == .global)
        #expect(registry.scope(forContextID: "missing") == .local)
    }

    @Test func allContextsExposesRegisteredContexts() {
        let ctx = ShortcutContext<Act>("editor")
        let registry = ShortcutRegistry(contexts: [ctx])
        #expect(registry.allContexts.map(\.id) == ["editor"])
    }
}
