import Foundation
@testable import ShortcutKit
import Testing

@MainActor
@Suite("HintsPreference") struct HintsPreferenceTests {
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

    @Test("effective hintsEnabled follows the app default when unset")
    func defaultApplies() {
        let ctx = ShortcutContext<Act>("editor")
        let onByDefault = ShortcutRegistry(contexts: [ctx], store: isolatedStore())
        #expect(onByDefault.hintsEnabled == true)

        let ctx2 = ShortcutContext<Act>("editor")
        let offByDefault = ShortcutRegistry(
            contexts: [ctx2], store: isolatedStore(), defaultHintsEnabled: false
        )
        #expect(offByDefault.hintsEnabled == false)
    }

    @Test("setHintsEnabled persists an override and survives reload")
    func overridePersists() throws {
        let store = isolatedStore()
        let registry = ShortcutRegistry(contexts: [ShortcutContext<Act>("editor")], store: store)
        registry.setHintsEnabled(false)
        #expect(registry.hintsEnabled == false)
        registry.flushPendingSave()

        let reloaded = ShortcutRegistry(contexts: [ShortcutContext<Act>("editor")], store: store)
        #expect(reloaded.hintsEnabled == false)
    }

    @Test("setting the value back to the default clears the stored override")
    func defaultClearsOverride() throws {
        let store = isolatedStore()
        let registry = ShortcutRegistry(contexts: [ShortcutContext<Act>("editor")], store: store)
        registry.setHintsEnabled(false)
        registry.setHintsEnabled(true)
        registry.flushPendingSave()

        #expect(try store.load().preferences.isDefault)
    }

    @Test("an off-by-default registry persists an on override")
    func overrideAgainstOffDefault() throws {
        let store = isolatedStore()
        let registry = ShortcutRegistry(
            contexts: [ShortcutContext<Act>("editor")], store: store, defaultHintsEnabled: false
        )
        registry.setHintsEnabled(true)
        registry.flushPendingSave()
        #expect(try store.load().preferences.hintsEnabled == true)

        let reloaded = ShortcutRegistry(
            contexts: [ShortcutContext<Act>("editor")], store: store, defaultHintsEnabled: false
        )
        #expect(reloaded.hintsEnabled == true)
    }

    @Test("effective hintFrequency follows the app default when unset")
    func frequencyDefaultApplies() {
        let ctx = ShortcutContext<Act>("editor")
        let defaulted = ShortcutRegistry(contexts: [ctx], store: isolatedStore())
        #expect(defaulted.hintFrequency == .oncePerSession)

        let ctx2 = ShortcutContext<Act>("editor")
        let custom = ShortcutRegistry(
            contexts: [ctx2], store: isolatedStore(), defaultHintFrequency: .timeout(30)
        )
        #expect(custom.hintFrequency == .timeout(30))
    }

    @Test("setHintFrequency persists an override and survives reload")
    func frequencyOverridePersists() throws {
        let store = isolatedStore()
        let registry = ShortcutRegistry(contexts: [ShortcutContext<Act>("editor")], store: store)
        registry.setHintFrequency(.always)
        #expect(registry.hintFrequency == .always)
        registry.flushPendingSave()

        let reloaded = ShortcutRegistry(contexts: [ShortcutContext<Act>("editor")], store: store)
        #expect(reloaded.hintFrequency == .always)
    }

    @Test("setting the frequency back to the default clears the stored override")
    func frequencyDefaultClearsOverride() throws {
        let store = isolatedStore()
        let registry = ShortcutRegistry(contexts: [ShortcutContext<Act>("editor")], store: store)
        registry.setHintFrequency(.always)
        registry.setHintFrequency(.oncePerSession)
        registry.flushPendingSave()
        #expect(try store.load().preferences.hintFrequency == nil)
    }

    @Test("an off-default (.timeout) registry persists a divergent override and clears on match")
    func frequencyOverrideAgainstOffDefault() throws {
        let store = isolatedStore()
        func makeRegistry() -> ShortcutRegistry {
            ShortcutRegistry(
                contexts: [ShortcutContext<Act>("editor")], store: store,
                defaultHintFrequency: .timeout(30)
            )
        }
        let registry = makeRegistry()
        registry.setHintFrequency(.oncePerSession)
        registry.flushPendingSave()
        #expect(try store.load().preferences.hintFrequency == .oncePerSession)
        #expect(makeRegistry().hintFrequency == .oncePerSession)

        registry.setHintFrequency(.timeout(30))
        registry.flushPendingSave()
        #expect(try store.load().preferences.hintFrequency == nil)
    }

    @Test("reload() picks up an out-of-band hintFrequency change")
    func reloadPicksUpFrequency() throws {
        let store = isolatedStore()
        let registry = ShortcutRegistry(contexts: [ShortcutContext<Act>("editor")], store: store)
        #expect(registry.hintFrequency == .oncePerSession)

        try store.save(RawState(preferences: Preferences(hintFrequency: .always)))
        registry.reload()
        #expect(registry.hintFrequency == .always)
    }
}
