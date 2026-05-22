import ShortcutField

/// The user's overrides, keyed by context ID and action ID. Carries no version
/// or library metadata — the on-disk content is the state (see spec §5.3).
///
/// Phase 1.5: each action maps to an array of bindings (`[Shortcut]`). Phase 1
/// on-disk data wrote a single scalar `Shortcut`; the JSON/TOML decoders
/// transparently upgrade that legacy shape to a single-element array on read.
public struct RawState: Sendable, Equatable {
    public var overrides: [String: [String: [Shortcut]]]
    public init(overrides: [String: [String: [Shortcut]]] = [:]) {
        self.overrides = overrides
    }
}

extension RawState: Codable {
    private enum CodingKeys: String, CodingKey { case overrides }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let raw = try container.decode([String: [String: ShortcutOrArray]].self, forKey: .overrides)
        overrides = raw.mapValues { $0.mapValues(\.values) }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(overrides, forKey: .overrides)
    }
}

/// Internal Decodable adapter: accepts either a single `Shortcut` (legacy
/// Phase 1 shape) or a `[Shortcut]` (Phase 1.5 shape) per binding value.
enum ShortcutOrArray: Decodable {
    case scalar(Shortcut)
    case array([Shortcut])

    var values: [Shortcut] {
        switch self {
        case let .scalar(value): [value]
        case let .array(values): values
        }
    }

    init(from decoder: Decoder) throws {
        let single = try decoder.singleValueContainer()
        if let arr = try? single.decode([Shortcut].self) {
            self = .array(arr)
            return
        }
        self = try .scalar(single.decode(Shortcut.self))
    }
}

/// Pluggable persistence for `RawState`.
@MainActor public protocol ShortcutBindingsStore {
    func load() throws -> RawState
    func save(_ state: RawState) throws
}
