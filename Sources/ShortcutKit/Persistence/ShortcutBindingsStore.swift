import ShortcutField

/// The user's overrides, keyed by context ID and action ID. Carries no version
/// or library metadata — the on-disk content is the state (see spec §5.3).
public struct RawState: Sendable, Equatable, Codable {
    public var overrides: [String: [String: Shortcut]]
    public init(overrides: [String: [String: Shortcut]] = [:]) {
        self.overrides = overrides
    }
}

/// Pluggable persistence for `RawState`.
@MainActor public protocol ShortcutBindingsStore {
    func load() throws -> RawState
    func save(_ state: RawState) throws
}
