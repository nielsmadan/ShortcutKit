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

    @Test("setOverride replaces the effective shortcut for that action")
    func setOverrideReplacesShortcut() {
        let ctx = ShortcutContext<DemoAction>("editor")
        let registry = ShortcutRegistry(contexts: [ctx], store: isolatedStore())
        registry.setOverride(contextID: "editor", actionID: "save", shortcut: "cmd+shift+s")
        let expected: Shortcut = "cmd+shift+s"
        #expect(ctx.shortcuts(for: .save).first == expected)
        #expect(ctx.isCustomized(.save))
    }

    @Test("setOverride nil clears the override")
    func setOverrideNilClears() {
        let ctx = ShortcutContext<DemoAction>("editor")
        let registry = ShortcutRegistry(contexts: [ctx], store: isolatedStore())
        registry.setOverride(contextID: "editor", actionID: "save", shortcut: "cmd+shift+s")
        registry.setOverride(contextID: "editor", actionID: "save", shortcut: nil)
        let expected: Shortcut = "cmd+s"
        #expect(ctx.shortcuts(for: .save).first == expected)
        #expect(ctx.isCustomized(.save) == false)
    }

    @Test("reset clears one override; resetAll clears them all")
    func resetMethods() {
        let ctx = ShortcutContext<DemoAction>("editor")
        let registry = ShortcutRegistry(contexts: [ctx], store: isolatedStore())
        registry.setOverride(contextID: "editor", actionID: "save", shortcut: "cmd+shift+s")
        registry.setOverride(contextID: "editor", actionID: "quit", shortcut: "cmd+shift+q")

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
        registry.setOverride(contextID: "editor", actionID: "save", shortcut: "cmd+shift+s")
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

        registry.setOverride(contextID: "editor", actionID: "save", shortcut: "cmd+shift+s")
        #expect(try store.load().overrides.isEmpty)

        registry.__flushPendingSave()
        let loaded = try store.load()
        let expected: Shortcut = "cmd+shift+s"
        #expect(loaded.overrides["editor"]?["save"] == [expected])
    }
}
