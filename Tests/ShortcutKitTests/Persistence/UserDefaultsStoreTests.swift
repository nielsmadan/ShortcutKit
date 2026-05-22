import Foundation
@testable import ShortcutKit
import Testing

@MainActor
@Suite("UserDefaultsStore") struct UserDefaultsStoreTests {
    private func isolatedDefaults() -> UserDefaults {
        let suite = "ShortcutKitTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test("empty state when nothing is stored")
    func emptyByDefault() throws {
        let store = UserDefaultsStore(defaults: isolatedDefaults())
        let state = try store.load()
        #expect(state.overrides.isEmpty)
    }

    @Test("save then load round-trips overrides")
    func roundTrip() throws {
        let store = UserDefaultsStore(defaults: isolatedDefaults())
        var state = RawState()
        state.overrides["editor"] = ["save": "cmd+shift+s"]
        state
            .overrides["viewer"] =
            ["zoom-in": .continuous(.init(kind: .pinchOut, modifiers: .command, sensitivity: 0.5))]
        try store.save(state)

        let loaded = try store.load()
        #expect(loaded == state)
    }

    @Test("custom key isolates instances")
    func customKey() throws {
        let defaults = isolatedDefaults()
        let storeA = UserDefaultsStore(defaults: defaults, key: "a")
        let storeB = UserDefaultsStore(defaults: defaults, key: "b")
        var state = RawState()
        state.overrides["editor"] = ["save": "cmd+s"]
        try storeA.save(state)
        #expect(try storeB.load().overrides.isEmpty)
        #expect(try storeA.load() == state)
    }
}
