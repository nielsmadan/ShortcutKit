import Combine
import Foundation
import ShortcutField

/// The hub: owns contexts, persistence, conflicts, and routing. `@MainActor`
/// throughout (meta-spec concurrency decision). Contexts always live inside a
/// registry; single-context apps still construct one.
@MainActor
public final class ShortcutRegistry: ObservableObject, RegistryOverrideSource {
    // Public outputs — empty here, populated by Tasks 12 (conflicts) and 15 (table).
    @Published public private(set) var conflicts: [Conflict] = []
    @Published public private(set) var keyBindingsTable: KeyBindingsTable = .init()
    public let actionFired: AnyPublisher<ActionFiredEvent, Never>

    // Stored for Tasks 7/8/12/15 to consume.
    let contexts: [any AnyShortcutContext]
    let mutuallyExclusiveContexts: [Set<String>]
    let migrations: [ShortcutMigration]
    let store: any ShortcutBindingsStore

    private let actionFiredSubject = PassthroughSubject<ActionFiredEvent, Never>()
    var overrides: [String: [String: Shortcut]] = [:]
    private var pendingSave: DispatchWorkItem?

    public init(
        contexts: [any AnyShortcutContext],
        mutuallyExclusiveContexts: [Set<String>] = [],
        migrations: [ShortcutMigration] = [],
        store: any ShortcutBindingsStore = UserDefaultsStore()
    ) {
        self.contexts = contexts
        self.mutuallyExclusiveContexts = mutuallyExclusiveContexts
        self.migrations = migrations
        self.store = store
        actionFired = actionFiredSubject.eraseToAnyPublisher()

        for context in contexts {
            attach(context: context)
        }

        do {
            let loaded = try store.load()
            overrides = loaded.overrides
        } catch {
            // Corrupt persistence — Task 7 adds os.Logger wiring.
            overrides = [:]
        }
    }

    private func attach(context: any AnyShortcutContext) {
        (context as? RegistryAttachable)?.__attach(registry: self)
    }

    // MARK: - RegistryOverrideSource

    func override(contextID: String, actionID: String) -> Shortcut? {
        overrides[contextID]?[actionID]
    }

    func recordActionFired(_ event: ActionFiredEvent) {
        actionFiredSubject.send(event)
    }

    // MARK: - Debounced save

    func scheduleSave() {
        pendingSave?.cancel()
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in self?.flushSave() }
        }
        pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.250, execute: work)
    }

    private func flushSave() {
        pendingSave = nil
        do {
            try store.save(RawState(overrides: overrides))
        } catch {
            // Best-effort; Task 7 adds os.Logger wiring.
        }
    }

    // swiftlint:disable identifier_name
    /// Test seam — synchronously flushes the pending debounced save.
    func __flushPendingSave() {
        pendingSave?.cancel()
        pendingSave = nil
        flushSave()
    }

    // swiftlint:enable identifier_name
}

// swiftlint:disable identifier_name
/// Internal protocol the concrete `ShortcutContext<Action>` implements so the
/// registry can wire its `registry` ref without seeing the generic parameter.
@MainActor protocol RegistryAttachable: AnyObject {
    func __attach(registry: any RegistryOverrideSource)
    func __notifyOverrideChange(actionID: String)
}

// swiftlint:enable identifier_name
