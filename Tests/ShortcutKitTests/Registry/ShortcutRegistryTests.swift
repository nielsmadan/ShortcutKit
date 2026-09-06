import Combine
import Foundation
@testable import ShortcutKit
import Testing

enum DemoAction: String, ShortcutAction {
    case save, quit
    var definition: ShortcutActionDefinition {
        switch self {
        case .save: .init("Save", "cmd+s")
        case .quit: .init("Quit", "cmd+q")
        }
    }
}

@MainActor
private final class RecordingStore: ShortcutBindingsStore {
    enum Error: Swift.Error { case loadFailed, saveFailed }

    var state = RawState()
    var saveCount = 0
    var shouldFailLoad = false
    var shouldFailSave = false

    func load() throws -> RawState {
        if shouldFailLoad { throw Error.loadFailed }
        return state
    }

    func save(_ state: RawState) throws {
        saveCount += 1
        if shouldFailSave { throw Error.saveFailed }
        self.state = state
    }

    func clear() throws { state = RawState() }
}

@MainActor
@Suite("ShortcutRegistry") struct ShortcutRegistryTests {
    private func isolatedStore() -> UserDefaultsStore {
        let suite = "ShortcutKitTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return UserDefaultsStore(defaults: defaults)
    }

    @Test("contexts get attached and see no override initially")
    func contextsAttachedNoOverrides() {
        let ctx = ShortcutContext<DemoAction>("editor")
        let registry = ShortcutRegistry(contexts: [ctx], store: isolatedStore())
        _ = registry
        let expected: Shortcut = "cmd+s"
        #expect(ctx.shortcuts(for: .save).first == expected)
        #expect(ctx.isCustomized(.save) == false)
    }

    @Test("a context rejects attachment to a second registry")
    func contextHasOneRegistryOwner() {
        let context = ShortcutContext<DemoAction>("editor")
        let first = ShortcutRegistry(contexts: [context], store: isolatedStore())
        let second = ShortcutRegistry(contexts: [], store: isolatedStore())

        #expect(context.__attach(registry: first))
        #expect(context.__attach(registry: second) == false)
        #expect(context.attachedRegistry === first)
    }

    @Test("setOverride replaces the effective shortcut for that action")
    func setOverrideReplacesShortcut() {
        let ctx = ShortcutContext<DemoAction>("editor")
        let registry = ShortcutRegistry(contexts: [ctx], store: isolatedStore())
        registry.setShortcuts(["cmd+shift+s"], contextID: "editor", actionID: "save")
        let expected: Shortcut = "cmd+shift+s"
        #expect(ctx.shortcuts(for: .save).first == expected)
        #expect(ctx.isCustomized(.save))
    }

    @Test("setOverride nil clears the override")
    func setOverrideNilClears() {
        let ctx = ShortcutContext<DemoAction>("editor")
        let registry = ShortcutRegistry(contexts: [ctx], store: isolatedStore())
        registry.setShortcuts(["cmd+shift+s"], contextID: "editor", actionID: "save")
        registry.reset(contextID: "editor", actionID: "save")
        let expected: Shortcut = "cmd+s"
        #expect(ctx.shortcuts(for: .save).first == expected)
        #expect(ctx.isCustomized(.save) == false)
    }

    @Test("reset clears one override; resetAll clears them all")
    func resetMethods() {
        let ctx = ShortcutContext<DemoAction>("editor")
        let registry = ShortcutRegistry(contexts: [ctx], store: isolatedStore())
        registry.setShortcuts(["cmd+shift+s"], contextID: "editor", actionID: "save")
        registry.setShortcuts(["cmd+shift+q"], contextID: "editor", actionID: "quit")

        registry.reset(contextID: "editor", actionID: "save")
        #expect(ctx.isCustomized(.save) == false)
        #expect(ctx.isCustomized(.quit) == true)

        registry.resetAll()
        #expect(ctx.isCustomized(.quit) == false)
    }

    @Test("reset all publishes one derived key-binding snapshot")
    func resetAllBatchesDerivedStateRefresh() {
        let context = ShortcutContext<DemoAction>("editor")
        let registry = ShortcutRegistry(contexts: [context], store: isolatedStore())
        registry.setShortcuts(["cmd+shift+s"], contextID: "editor", actionID: "save")
        registry.setShortcuts(["cmd+shift+q"], contextID: "editor", actionID: "quit")
        var snapshots = 0
        let token = registry.$keyBindings.dropFirst().sink { _ in snapshots += 1 }

        registry.resetAll()

        #expect(snapshots == 1)
        #expect(registry.keyBindings.groups[0].entries.allSatisfy { !$0.isCustomized })
        _ = token
    }

    @Test("setOverride emits via shortcutsChanges(for:)")
    func shortcutChangesEmits() {
        let ctx = ShortcutContext<DemoAction>("editor")
        let registry = ShortcutRegistry(contexts: [ctx], store: isolatedStore())

        var values: [[Shortcut]] = []
        let cancellable = ctx.shortcutsChanges(for: .save).sink { values.append($0) }
        registry.setShortcuts(["cmd+shift+s"], contextID: "editor", actionID: "save")
        #expect(values.count == 2)
        let expected: Shortcut = "cmd+shift+s"
        #expect(values.last == [expected])
        _ = cancellable
    }

    @Test("dispatch on a context emits actionFired with source: .programmatic")
    func dispatchEmitsActionFired() {
        let ctx = ShortcutContext<DemoAction>("editor")
        let registry = ShortcutRegistry(contexts: [ctx], store: isolatedStore())
        var events: [ActionFiredEvent] = []
        let cancellable = registry.actionFired.sink { events.append($0) }
        ctx.dispatch(.save)
        #expect(events == [.init(contextID: "editor", actionID: "save", source: .programmatic)])
        _ = cancellable
    }

    @Test("loaded overrides are seen by attached contexts on init")
    func loadedOverridesVisibleOnInit() throws {
        let store = isolatedStore()
        var initial = RawState()
        initial.overrides["editor"] = ["save": ["cmd+shift+s"]]
        try store.save(initial)

        let ctx = ShortcutContext<DemoAction>("editor")
        let registry = ShortcutRegistry(contexts: [ctx], store: store)
        _ = registry
        let expected: Shortcut = "cmd+shift+s"
        #expect(ctx.shortcuts(for: .save).first == expected)
    }

    @Test("debounced save can be flushed deterministically via the test seam")
    func debouncedSaveFlushTestSeam() throws {
        let store = isolatedStore()
        let ctx = ShortcutContext<DemoAction>("editor")
        let registry = ShortcutRegistry(contexts: [ctx], store: store)

        registry.setShortcuts(["cmd+shift+s"], contextID: "editor", actionID: "save")
        #expect(try store.load().overrides.isEmpty)

        #expect(registry.flushPendingSave())
        let loaded = try store.load()
        let expected: Shortcut = "cmd+shift+s"
        #expect(loaded.overrides["editor"]?["save"] == [expected])
    }

    @Test("flush with no pending changes does not write")
    func cleanFlushIsNoOp() {
        let store = RecordingStore()
        let registry = ShortcutRegistry(contexts: [], store: store)

        #expect(registry.flushPendingSave())
        #expect(store.saveCount == 0)
    }

    @Test("failed flush reports failure and remains retryable")
    func failedFlushCanRetry() {
        let store = RecordingStore()
        let context = ShortcutContext<DemoAction>("editor")
        let registry = ShortcutRegistry(contexts: [context], store: store)
        registry.setShortcuts(["cmd+shift+s"], contextID: "editor", actionID: "save")
        store.shouldFailSave = true

        #expect(registry.flushPendingSave() == false)
        #expect(store.saveCount == 1)
        store.shouldFailSave = false
        #expect(registry.flushPendingSave())
        #expect(store.saveCount == 2)
        #expect(store.state.overrides["editor"]?["save"] == ["cmd+shift+s"])
        #expect(registry.flushPendingSave())
        #expect(store.saveCount == 2)
    }

    @Test("successful reload flushes pending changes instead of discarding them")
    func reloadFlushesPendingChanges() {
        let store = RecordingStore()
        let context = ShortcutContext<DemoAction>("editor")
        let registry = ShortcutRegistry(contexts: [context], store: store)
        registry.setShortcuts(["cmd+shift+s"], contextID: "editor", actionID: "save")

        #expect(registry.reload())
        #expect(registry.flushPendingSave())
        #expect(store.saveCount == 1)
        #expect(context.shortcuts(for: .save) == ["cmd+shift+s"])
    }

    @Test("failed reload preserves pending changes")
    func failedReloadPreservesPendingChanges() {
        let store = RecordingStore()
        let context = ShortcutContext<DemoAction>("editor")
        let registry = ShortcutRegistry(contexts: [context], store: store)
        registry.setShortcuts(["cmd+shift+s"], contextID: "editor", actionID: "save")
        store.shouldFailLoad = true

        #expect(registry.reload() == false)
        store.shouldFailLoad = false
        #expect(registry.flushPendingSave())
        #expect(store.saveCount == 1)
        #expect(store.state.overrides["editor"]?["save"] == ["cmd+shift+s"])
    }

    @Test("prepare has no effect and commit publishes one binding change")
    func prepareThenCommit() throws {
        let store = RecordingStore()
        let context = ShortcutContext<DemoAction>("editor")
        let registry = ShortcutRegistry(contexts: [context], store: store)
        var values: [[Shortcut]] = []
        let token = context.shortcutsChanges(for: .save).sink { values.append($0) }
        let preparation = try registry.prepare(RawState(
            overrides: ["editor": ["save": ["cmd+shift+s"]]]
        ))

        #expect(preparation.requiresPersistenceWriteback == false)
        #expect(context.shortcuts(for: .save) == ["cmd+s"])
        #expect(values == [["cmd+s"]])

        try registry.commit(preparation.preparedState)

        #expect(context.shortcuts(for: .save) == ["cmd+shift+s"])
        #expect(values == [["cmd+s"], ["cmd+shift+s"]])
        _ = token
    }

    @Test("prepare returns an exact migration write-back without applying it")
    func prepareMigrationWriteback() throws {
        let store = RecordingStore()
        let context = ShortcutContext<DemoAction>("editor")
        let migration: ShortcutMigration = .renameAction(
            context: "editor",
            from: "save-legacy",
            to: "save"
        )
        let registry = ShortcutRegistry(contexts: [context], migrations: [migration], store: store)
        let input = RawState(overrides: ["editor": ["save-legacy": ["cmd+shift+s"]]])

        let preparation = try registry.prepare(input)

        #expect(preparation.requiresPersistenceWriteback)
        #expect(preparation.persistenceWriteback?.overrides == [
            "editor": ["save": ["cmd+shift+s"]],
        ])
        #expect(context.shortcuts(for: .save) == ["cmd+s"])
    }

    @Test("reload applies migrations through the same preparation path")
    func reloadAppliesMigrations() throws {
        let store = RecordingStore()
        store.state = RawState(overrides: ["editor": ["save-legacy": ["cmd+shift+s"]]])
        let context = ShortcutContext<DemoAction>("editor")
        let migration: ShortcutMigration = .renameAction(
            context: "editor",
            from: "save-legacy",
            to: "save"
        )
        let registry = ShortcutRegistry(contexts: [context], migrations: [migration], store: store)

        #expect(context.shortcuts(for: .save) == ["cmd+shift+s"])
        #expect(store.state.overrides == ["editor": ["save": ["cmd+shift+s"]]])
        store.state = RawState(overrides: ["editor": ["save-legacy": ["ctrl+s"]]])

        #expect(registry.reload())
        #expect(context.shortcuts(for: .save) == ["ctrl+s"])
        #expect(store.state.overrides == ["editor": ["save": ["ctrl+s"]]])
    }

    @Test("a throwing reload migration retains current runtime state")
    func reloadMigrationFailureIsAtomic() {
        struct MigrationError: Error {}
        let store = RecordingStore()
        let migration: ShortcutMigration = .custom { state in
            if state.overrides["invalid"] != nil { throw MigrationError() }
        }
        let context = ShortcutContext<DemoAction>("editor")
        let registry = ShortcutRegistry(contexts: [context], migrations: [migration], store: store)
        registry.setShortcuts(["cmd+shift+s"], contextID: "editor", actionID: "save")
        #expect(registry.flushPendingSave())
        store.state = RawState(overrides: ["invalid": ["value": ["cmd+i"]]])

        let result = registry.reloadResult()
        if case let .migrationFailed(error) = result {
            #expect(error is MigrationError)
        } else {
            Issue.record("expected a migration failure, received \(result)")
        }
        #expect(result.didReload == false)
        #expect(context.shortcuts(for: .save) == ["cmd+shift+s"])
        #expect(registry.hasPendingSave == false)
    }

    @Test("initialization keeps loaded state and continues after a throwing migration")
    func initializationMigrationsRemainBestEffort() {
        struct MigrationError: Error {}
        let store = RecordingStore()
        store.state = RawState(overrides: ["editor": ["save-legacy": ["shift+cmd+s"]]])
        let context = ShortcutContext<DemoAction>("editor")
        let migrations: [ShortcutMigration] = [
            .custom { _ in throw MigrationError() },
            .renameAction(context: "editor", from: "save-legacy", to: "save"),
        ]

        let registry = ShortcutRegistry(contexts: [context], migrations: migrations, store: store)

        #expect(context.shortcuts(for: .save) == ["shift+cmd+s"])
        #expect(store.state.overrides == ["editor": ["save": ["shift+cmd+s"]]])
        #expect(registry.hasPendingSave == false)
    }

    @Test("a failed initialization migration write-back remains pending")
    func initializationMigrationWritebackCanRetry() {
        let store = RecordingStore()
        store.state = RawState(overrides: ["editor": ["save-legacy": ["shift+cmd+s"]]])
        store.shouldFailSave = true
        let context = ShortcutContext<DemoAction>("editor")
        let migration = ShortcutMigration.renameAction(context: "editor", from: "save-legacy", to: "save")

        let registry = ShortcutRegistry(contexts: [context], migrations: [migration], store: store)

        #expect(context.shortcuts(for: .save) == ["shift+cmd+s"])
        #expect(registry.hasPendingSave)
        #expect(store.saveCount == 1)
        store.shouldFailSave = false
        #expect(registry.flushPendingSave())
        #expect(store.saveCount == 2)
        #expect(store.state.overrides == ["editor": ["save": ["shift+cmd+s"]]])
    }

    @Test("reload reports pending-save and load failures separately")
    func reloadFailureResults() {
        let store = RecordingStore()
        let context = ShortcutContext<DemoAction>("editor")
        let registry = ShortcutRegistry(contexts: [context], store: store)
        registry.setShortcuts(["shift+cmd+s"], contextID: "editor", actionID: "save")
        store.shouldFailSave = true

        let pendingResult = registry.reloadResult()
        if case let .pendingSaveFailed(error) = pendingResult {
            #expect(error is RecordingStore.Error)
        } else {
            Issue.record("expected a pending-save failure, received \(pendingResult)")
        }

        store.shouldFailSave = false
        #expect(registry.flushPendingSave())
        store.shouldFailLoad = true
        let loadResult = registry.reloadResult()
        if case let .loadFailed(error) = loadResult {
            #expect(error is RecordingStore.Error)
        } else {
            Issue.record("expected a load failure, received \(loadResult)")
        }
    }

    @Test("reload applies migrated state while reporting a failed write-back")
    func reloadMigrationWritebackFailure() {
        let store = RecordingStore()
        let context = ShortcutContext<DemoAction>("editor")
        let migration = ShortcutMigration.renameAction(context: "editor", from: "save-legacy", to: "save")
        let registry = ShortcutRegistry(contexts: [context], migrations: [migration], store: store)
        store.state = RawState(overrides: ["editor": ["save-legacy": ["ctrl+s"]]])
        store.shouldFailSave = true
        var saveResults: [ShortcutSaveResult] = []
        let token = registry.saveResults.sink { saveResults.append($0) }

        let result = registry.reloadResult()

        if case let .reloadedWithWritebackFailure(error) = result {
            #expect(error is RecordingStore.Error)
        } else {
            Issue.record("expected a write-back failure, received \(result)")
        }
        #expect(result.didReload)
        #expect(context.shortcuts(for: .save) == ["ctrl+s"])
        #expect(registry.hasPendingSave)
        #expect(saveResults.count == 1)
        store.shouldFailSave = false
        #expect(registry.flushPendingSave())
        #expect(store.state.overrides == ["editor": ["save": ["ctrl+s"]]])
        _ = token
    }

    @Test("prepared state is registry-owned, current, and single-use")
    func preparedStateValidation() throws {
        let first = ShortcutRegistry(contexts: [], store: RecordingStore())
        let second = ShortcutRegistry(contexts: [], store: RecordingStore())
        let foreign = try first.prepare(RawState()).preparedState

        #expect(throws: ShortcutRegistry.PreparedStateError.wrongRegistry) {
            try second.commit(foreign)
        }

        let reusable = try first.prepare(RawState()).preparedState
        try first.commit(reusable)
        #expect(throws: ShortcutRegistry.PreparedStateError.alreadyApplied) {
            try first.commit(reusable)
        }

        let stale = try first.prepare(RawState()).preparedState
        first.setHintsEnabled(false)
        #expect(first.flushPendingSave())
        #expect(throws: ShortcutRegistry.PreparedStateError.stale) {
            try first.commit(stale)
        }

        first.setHintsEnabled(true)
        let pending = try first.prepare(RawState()).preparedState
        #expect(throws: ShortcutRegistry.PreparedStateError.pendingChanges) {
            try first.commit(pending)
        }
    }

    @Test("save results arrive after the store attempt and retain the error")
    func structuredSaveResults() throws {
        let store = RecordingStore()
        let context = ShortcutContext<DemoAction>("editor")
        let registry = ShortcutRegistry(contexts: [context], store: store)
        var results: [ShortcutSaveResult] = []
        var pendingStates: [Bool] = []
        let token = registry.saveResults.sink {
            results.append($0)
            pendingStates.append(registry.hasPendingSave)
        }
        registry.setShortcuts(["cmd+shift+s"], contextID: "editor", actionID: "save")
        store.shouldFailSave = true

        #expect(registry.flushPendingSave() == false)
        #expect(results.count == 1)
        let failed = try #require(results.first)
        #expect(failed.error is RecordingStore.Error)
        #expect(failed.state.overrides["editor"]?["save"] == ["cmd+shift+s"])
        #expect(pendingStates == [true])
        store.shouldFailSave = false

        #expect(registry.flushPendingSave())
        #expect(results.count == 2)
        let saved = try #require(results.last)
        #expect(saved.error == nil)
        #expect(pendingStates == [true, false])
        _ = token
    }

    @Test("failed pending state can be explicitly discarded while applying last-valid state")
    func discardPendingSave() throws {
        let store = RecordingStore()
        let context = ShortcutContext<DemoAction>("editor")
        let registry = ShortcutRegistry(contexts: [context], store: store)
        let lastValid = try registry.prepare(RawState(
            overrides: ["editor": ["save": ["ctrl+s"]]]
        )).preparedState
        registry.setShortcuts(["cmd+shift+s"], contextID: "editor", actionID: "save")
        store.shouldFailSave = true
        #expect(registry.flushPendingSave() == false)

        try registry.discardPendingSave(applying: lastValid)

        #expect(registry.hasPendingSave == false)
        #expect(context.shortcuts(for: .save) == ["ctrl+s"])
        let saveCount = store.saveCount
        #expect(registry.flushPendingSave())
        #expect(store.saveCount == saveCount)
    }
}
