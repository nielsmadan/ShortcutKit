import Foundation
import ShortcutField
@testable import ShortcutKit
import Testing

enum SnapshotAction: String, ShortcutAction {
    case save
    var definition: ShortcutActionDefinition { .init("Save", "cmd+s") }
}

@MainActor
@Suite("Activation snapshot") struct ActivationSnapshotTests {
    private func isolatedStore() -> UserDefaultsStore {
        let suite = "ShortcutKitTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return UserDefaultsStore(defaults: defaults)
    }

    @Test("an inactive registry has an empty snapshot")
    func emptyWhenNothingActive() {
        let ctx = ShortcutContext<SnapshotAction>("editor")
        let registry = ShortcutRegistry(contexts: [ctx], store: isolatedStore())

        #expect(registry.activationSnapshot.isEmpty)
    }

    @Test("entries follow router order, outermost first")
    func ordersOutermostFirst() {
        let outer = ShortcutContext<SnapshotAction>("outer")
        let inner = ShortcutContext<SnapshotAction>("inner")
        let registry = ShortcutRegistry(contexts: [outer, inner], store: isolatedStore())

        outer.__activate(activationID: UUID())
        inner.__activate(activationID: UUID())

        #expect(registry.activationSnapshot.entries.map(\.contextID) == ["outer", "inner"])
        #expect(registry.activationSnapshot.innermostFirst.map(\.contextID) == ["inner", "outer"])
    }

    /// The property `activeBindings()` destroys by collapsing to a `Set`: two
    /// views activating one context both sit on the stack, and their order is
    /// what decides which wins a tie.
    @Test("a context activated twice appears twice")
    func preservesDuplicates() {
        let ctx = ShortcutContext<SnapshotAction>("editor")
        let registry = ShortcutRegistry(contexts: [ctx], store: isolatedStore())
        let first = UUID()
        let second = UUID()

        ctx.__activate(activationID: first)
        ctx.__activate(activationID: second)

        let entries = registry.activationSnapshot.entries
        #expect(entries.map(\.contextID) == ["editor", "editor"])
        #expect(entries.map(\.activationID) == [first, second])
        #expect(registry.activeBindings().groups.count == 1)
    }

    @Test("deactivating removes only that activation")
    func deactivateRemovesOneEntry() {
        let ctx = ShortcutContext<SnapshotAction>("editor")
        let registry = ShortcutRegistry(contexts: [ctx], store: isolatedStore())
        let first = UUID()
        let second = UUID()
        ctx.__activate(activationID: first)
        ctx.__activate(activationID: second)

        ctx.__deactivate(activationID: first)

        #expect(registry.activationSnapshot.entries.map(\.activationID) == [second])
    }

    @Test("entries carry the context's display name and scope")
    func carriesDisplayMetadata() {
        let ctx = ShortcutContext<SnapshotAction>("canvas.shared")
        let registry = ShortcutRegistry(contexts: [ctx], store: isolatedStore())
        ctx.__activate(activationID: UUID())

        let entry = registry.activationSnapshot.entries.first
        #expect(entry?.scope == .local)
        #expect(entry.map { String(localized: $0.displayName) } == "Canvas / Shared")
    }
}
