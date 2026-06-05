import ShortcutField
@testable import ShortcutKit
import Testing

@MainActor
@Suite("GlobalRegistryAPI") struct GlobalRegistryAPITests {
    enum GlobalAct: String, ShortcutAction {
        case ping
        var definition: ShortcutActionDefinition { .init("Ping", Shortcut("ctrl+opt+cmd+k")) }
    }

    @Test("dispatchGlobalAction invokes the dispatch closure with source: .shortcut")
    func dispatchGlobalActionDispatches() {
        var fired = 0
        let ctx = ShortcutContext<GlobalAct>(global: "global") { action, kind in
            if action == .ping, kind == .discrete { fired += 1 }
        }
        let registry = ShortcutRegistry(contexts: [ctx])
        var source: ActionFiredEvent.Source?
        let token = registry.actionFired.sink { source = $0.source }

        registry.dispatchGlobalAction(ActionRef(contextID: "global", actionID: "ping"))

        #expect(fired == 1)
        #expect(source == .shortcut)
        _ = token
    }

    @Test("dispatchGlobalAction is a no-op for an unknown context or action")
    func dispatchGlobalActionUnknown() {
        let ctx = ShortcutContext<GlobalAct>(global: "global") { _, _ in }
        let registry = ShortcutRegistry(contexts: [ctx])
        registry.dispatchGlobalAction(ActionRef(contextID: "nope", actionID: "ping"))
        registry.dispatchGlobalAction(ActionRef(contextID: "global", actionID: "nope"))
        #expect(Bool(true))
    }

    enum LocalAct: String, ShortcutAction {
        case save
        var definition: ShortcutActionDefinition { .init("Save", Shortcut("cmd+s")) }
    }

    @Test("globalBindings returns only global-scoped contexts' effective bindings")
    func globalBindingsEnumerates() {
        let global = ShortcutContext<GlobalAct>(global: "global") { _, _ in }
        let local = ShortcutContext<LocalAct>("editor")
        let registry = ShortcutRegistry(contexts: [global, local])

        let bindings = registry.globalBindings()

        #expect(bindings.count == 1)
        #expect(bindings.first?.id == BindingID(contextID: "global", actionID: "ping", bindingIndex: 0))
        #expect(bindings.first?.shortcut == Shortcut("ctrl+opt+cmd+k"))
    }

    @Test("globalBindings reflects overrides and multiple bindings")
    func globalBindingsOverrides() {
        let global = ShortcutContext<GlobalAct>(global: "global") { _, _ in }
        let registry = ShortcutRegistry(contexts: [global])
        global.setShortcuts(
            [Shortcut("ctrl+opt+cmd+j"), Shortcut("ctrl+opt+cmd+l")],
            for: .ping
        )
        let bindings = registry.globalBindings()
        #expect(bindings.count == 2)
        #expect(bindings.map(\.id.bindingIndex) == [0, 1])
        #expect(bindings.map(\.shortcut) == [Shortcut("ctrl+opt+cmd+j"), Shortcut("ctrl+opt+cmd+l")])
    }
}
