import Foundation
import ShortcutField
@testable import ShortcutKit
import Testing

enum VisibilityAction: String, ShortcutAction {
    case save, unbound

    var definition: ShortcutActionDefinition {
        switch self {
        case .save: .init("Save", "cmd+s")
        case .unbound: .init("Unbound", kind: .discrete)
        }
    }
}

/// Settings and the legend deliberately read different APIs: settings renders
/// every registered context so an action can always be found and rebound, while
/// the legend answers "what can I do right now". Deactivating a context must
/// therefore hide it from the legend without hiding it from settings.
@MainActor
@Suite("Deactivated context visibility") struct DeactivatedContextVisibilityTests {
    private func isolatedStore() -> UserDefaultsStore {
        let suite = "ShortcutKitTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return UserDefaultsStore(defaults: defaults)
    }

    @Test("a deactivated context drops out of activeBindings")
    func deactivatedDropsFromActiveBindings() {
        let ctx = ShortcutContext<VisibilityAction>("editor")
        let registry = ShortcutRegistry(contexts: [ctx], store: isolatedStore())

        let activationID = UUID()
        ctx.__activate(activationID: activationID)
        #expect(registry.activeBindings().groups.map(\.contextID) == ["editor"])

        ctx.__deactivate(activationID: activationID)
        #expect(registry.activeBindings().groups.isEmpty)
    }

    @Test("a deactivated context is still reachable through bindings(for:)")
    func deactivatedStillVisibleToSettings() {
        let ctx = ShortcutContext<VisibilityAction>("editor")
        let registry = ShortcutRegistry(contexts: [ctx], store: isolatedStore())
        // Never activated, so it is already inactive.

        let settings = registry.bindings(for: ["editor"])

        #expect(settings.groups.map(\.contextID) == ["editor"])
        #expect(settings.groups.first?.entries.map(\.actionID).sorted() == ["save", "unbound"])
    }

    @Test("bindings(for:) keeps unbound actions so they can be bound in settings")
    func unboundActionsSurviveForSettings() {
        let ctx = ShortcutContext<VisibilityAction>("editor")
        let registry = ShortcutRegistry(contexts: [ctx], store: isolatedStore())

        let entries = registry.bindings(for: ["editor"]).groups.first?.entries ?? []

        #expect(entries.first { $0.actionID == "unbound" }?.effectiveShortcuts.isEmpty == true)
    }

    @Test("boundOnly drops unbound actions, which is what the legend renders")
    func boundOnlyDropsUnbound() {
        let ctx = ShortcutContext<VisibilityAction>("editor")
        let registry = ShortcutRegistry(contexts: [ctx], store: isolatedStore())
        ctx.__activate(activationID: UUID())

        let legend = registry.activeBindings().boundOnly()

        #expect(legend.groups.first?.entries.map(\.actionID) == ["save"])
    }

    @Test("a global-scoped context stays in activeBindings without being activated")
    func globalScopeStaysActive() {
        let ctx = ShortcutContext<VisibilityAction>(global: "menu") { _, _ in }
        let registry = ShortcutRegistry(contexts: [ctx], store: isolatedStore())

        #expect(registry.activeBindings().groups.map(\.contextID) == ["menu"])
    }
}
