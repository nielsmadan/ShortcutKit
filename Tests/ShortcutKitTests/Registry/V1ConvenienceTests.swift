import Combine
import Foundation
@testable import ShortcutKit
import Testing

@MainActor
@Suite("V1Convenience") struct V1ConvenienceTests {
    enum Act: String, ShortcutAction {
        case save
        var definition: ShortcutActionDefinition { .init("Save", "cmd+s") }
    }

    private func isolatedStore() -> UserDefaultsStore {
        let suite = "ShortcutKitTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return UserDefaultsStore(defaults: defaults)
    }

    // MARK: - reload()

    @Test("reload() applies out-of-band store changes to bindings and prefs")
    func reloadAppliesExternalState() throws {
        let store = isolatedStore()
        let registry = ShortcutRegistry(contexts: [ShortcutContext<Act>("editor")], store: store)
        #expect(registry.keyBindings.groups.first?.entries.first?.effectiveShortcuts == [Shortcut("cmd+s")])
        #expect(registry.hintsEnabled == true)

        // Another writer edits the store directly (hand-edited file / sync).
        var external = RawState()
        external[context: "editor", action: "save"] = [Shortcut("cmd+shift+s")]
        external.preferences.hintsEnabled = false
        try store.save(external)

        #expect(registry.reload()) // returns true on a successful re-read

        let entry = registry.keyBindings.groups.first?.entries.first
        #expect(entry?.effectiveShortcuts == [Shortcut("cmd+shift+s")])
        #expect(entry?.isCustomized == true)
        #expect(registry.hintsEnabled == false)
    }

    @Test("reload() publishes the new bindings to shortcutsChanges subscribers")
    func reloadPublishesChange() throws {
        let store = isolatedStore()
        let ctx = ShortcutContext<Act>("editor")
        let registry = ShortcutRegistry(contexts: [ctx], store: store)
        var received: [[Shortcut]] = []
        let cancellable = ctx.shortcutsChanges(for: .save).sink { received.append($0) }

        var external = RawState()
        external[context: "editor", action: "save"] = [Shortcut("cmd+ctrl+s")]
        try store.save(external)
        registry.reload()

        #expect(received.last == [Shortcut("cmd+ctrl+s")])
        _ = cancellable
    }

    // MARK: - ActionFiredEvent: Hashable

    @Test("ActionFiredEvent is Hashable (dedups in a Set)")
    func actionFiredEventDedups() {
        let a = ActionFiredEvent(contextID: "editor", actionID: "save", source: .shortcut)
        let b = ActionFiredEvent(contextID: "editor", actionID: "save", source: .shortcut)
        let c = ActionFiredEvent(contextID: "editor", actionID: "save", source: .programmatic)
        #expect(Set([a, b, c]).count == 2)
    }

    // MARK: - UserDefaultsStore.clear()

    @Test("clear() wipes persisted state")
    func clearWipesStore() throws {
        let store = isolatedStore()
        try store.save(RawState(overrides: ["editor": ["save": [Shortcut("cmd+s")]]]))
        #expect(try store.load().overrides.isEmpty == false)
        store.clear()
        #expect(try store.load().overrides.isEmpty)
    }

    // MARK: - RawState.debugDescription

    @Test("debugDescription renders contexts, actions, and preferences")
    func debugDescriptionReadable() {
        var state = RawState(overrides: ["editor": ["save": [Shortcut("cmd+s")]]])
        state.preferences.hintsEnabled = false
        let dump = state.debugDescription
        #expect(dump.contains("[editor]"))
        #expect(dump.contains("save = "))
        #expect(dump.contains("[preferences]"))
        #expect(dump.contains("hints-enabled = false"))
        #expect(RawState().debugDescription == "(no overrides)")
    }

    // MARK: - SystemHotKey(_ shortcut:)

    @Test("SystemHotKey(shortcut) maps a single-key discrete shortcut")
    func systemHotKeyFromShortcut() {
        let hotKey = SystemHotKey(Shortcut("cmd+s"))
        #expect(hotKey != nil)
        #expect(hotKey?.modifiers.contains(.command) == true)
    }

    @Test("SystemHotKey(shortcut) is nil for a continuous shortcut")
    func systemHotKeyNilForContinuous() {
        let continuous: Shortcut = .continuous(.init(kind: .pinchOut, modifiers: .command, sensitivity: 0.5))
        #expect(SystemHotKey(continuous) == nil)
    }
}
