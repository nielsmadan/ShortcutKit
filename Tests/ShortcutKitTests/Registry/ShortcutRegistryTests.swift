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

    @Test("successful reload discards pending changes")
    func reloadDiscardsPendingChanges() {
        let store = RecordingStore()
        let context = ShortcutContext<DemoAction>("editor")
        let registry = ShortcutRegistry(contexts: [context], store: store)
        registry.setShortcuts(["cmd+shift+s"], contextID: "editor", actionID: "save")

        #expect(registry.reload())
        #expect(registry.flushPendingSave())
        #expect(store.saveCount == 0)
        #expect(context.shortcuts(for: .save) == ["cmd+s"])
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
}
