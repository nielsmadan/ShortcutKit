import Foundation
import ShortcutField

/// Stores `RawState` as a single JSON `Data` blob under a stable key.
/// Machine-format only — not for human editing. For human-editable storage,
/// use `FileStore` (Task 6).
public final class UserDefaultsStore: ShortcutBindingsStore {
    public static let defaultKey = "shortcutkit.overrides"

    private let defaults: UserDefaults
    private let key: String

    public init(defaults: UserDefaults = .standard, key: String = UserDefaultsStore.defaultKey) {
        self.defaults = defaults
        self.key = key
    }

    public func load() throws -> RawState {
        guard let data = defaults.data(forKey: key) else { return RawState() }
        return try JSONDecoder().decode(RawState.self, from: data)
    }

    public func save(_ state: RawState) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(state)
        defaults.set(data, forKey: key)
    }

    /// Remove all persisted ShortcutKit state (overrides + preferences) under this
    /// store's key. The next `load()` returns an empty `RawState`, so a registry
    /// re-reads its declared defaults.
    public func clear() {
        defaults.removeObject(forKey: key)
    }
}
