import ShortcutField

/// User preferences persisted alongside binding overrides.
///
/// A `nil` value follows the app default and is omitted from persistence.
public struct Preferences: Sendable, Equatable, Codable {
    /// User's hint-visibility choice, or `nil` to follow the app default.
    public var hintsEnabled: Bool?
    /// User's hint-frequency choice, or `nil` to follow the app default.
    public var hintFrequency: HintPolicy?

    public init(hintsEnabled: Bool? = nil, hintFrequency: HintPolicy? = nil) {
        self.hintsEnabled = hintsEnabled
        self.hintFrequency = hintFrequency
    }

    /// True when no preference diverges from its default (nothing to persist).
    public var isDefault: Bool { hintsEnabled == nil && hintFrequency == nil }

    private enum CodingKeys: String, CodingKey { case hintsEnabled, hintFrequency }

    // Invalid hint preferences must not prevent binding overrides from loading.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hintsEnabled = try container.decodeIfPresent(Bool.self, forKey: .hintsEnabled)
        let raw = (try? container.decodeIfPresent(String.self, forKey: .hintFrequency)) ?? nil
        hintFrequency = raw.flatMap(HintPolicy.init(persistedString:))
    }
}

/// Persisted binding overrides and ShortcutKit preferences.
///
/// Overrides are keyed by context and action persistence IDs. Decoding accepts
/// the legacy single-shortcut value and upgrades it to a one-element array.
public struct RawState: Sendable, Equatable {
    public var overrides: [String: [String: [Shortcut]]]
    public var preferences: Preferences

    public init(
        overrides: [String: [String: [Shortcut]]] = [:],
        preferences: Preferences = .init()
    ) {
        self.overrides = overrides
        self.preferences = preferences
    }
}

extension RawState: Codable {
    private enum CodingKeys: String, CodingKey { case overrides, preferences }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let raw = try container.decode([String: [String: ShortcutOrArray]].self, forKey: .overrides)
        overrides = raw.mapValues { $0.mapValues(\.values) }
        preferences = try container.decodeIfPresent(Preferences.self, forKey: .preferences) ?? Preferences()
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(overrides, forKey: .overrides)
        if !preferences.isDefault {
            try container.encode(preferences, forKey: .preferences)
        }
    }
}

/// Decodes current shortcut arrays and the legacy single-shortcut representation.
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

// MARK: - Ergonomic accessors

public extension RawState {
    /// All context IDs with at least one persisted override, in unspecified order.
    var contextIDs: [String] { Array(overrides.keys) }

    /// All action IDs with persisted overrides in `contextID`, in unspecified order.
    /// Empty if the context has no overrides.
    func actionIDs(in contextID: String) -> [String] {
        overrides[contextID].map { Array($0.keys) } ?? []
    }

    /// Reads or writes one action's bindings.
    ///
    /// Setting `nil` or an empty array removes the override and prunes an empty
    /// context. This is the supported mutation path for custom migrations and stores.
    subscript(context contextID: String, action actionID: String) -> [Shortcut]? {
        get { overrides[contextID]?[actionID] }
        set {
            if let newValue, !newValue.isEmpty {
                overrides[contextID, default: [:]][actionID] = newValue
            } else {
                overrides[contextID]?.removeValue(forKey: actionID)
                if overrides[contextID]?.isEmpty == true {
                    overrides.removeValue(forKey: contextID)
                }
            }
        }
    }

    /// Remove every override for one context.
    mutating func removeContext(_ contextID: String) {
        overrides.removeValue(forKey: contextID)
    }
}

extension RawState: CustomDebugStringConvertible {
    /// A stable, human-readable summary for diagnostics.
    public var debugDescription: String {
        var lines: [String] = []
        for contextID in overrides.keys.sorted() {
            lines.append("[\(contextID)]")
            let perAction = overrides[contextID] ?? [:]
            for actionID in perAction.keys.sorted() {
                let rendered = (perAction[actionID] ?? []).map(\.displayString).joined(separator: ", ")
                lines.append("  \(actionID) = \(rendered)")
            }
        }
        if !preferences.isDefault {
            lines.append("[preferences]")
            if let hints = preferences.hintsEnabled {
                lines.append("  hints-enabled = \(hints)")
            }
            if let frequency = preferences.hintFrequency {
                lines.append("  hint-frequency = \(frequency.persistedString)")
            }
        }
        return lines.isEmpty ? "(no overrides)" : lines.joined(separator: "\n")
    }
}

// MARK: - Store protocol

/// Pluggable persistence for `RawState`.
@MainActor public protocol ShortcutBindingsStore {
    func load() throws -> RawState
    func save(_ state: RawState) throws
    func clear() throws
}

public extension ShortcutBindingsStore {
    /// Removes all persisted ShortcutKit state.
    ///
    /// The default saves an empty state, preserving sibling data in namespaced stores.
    func clear() throws { try save(RawState()) }
}
