import ShortcutField

/// The user's overrides, keyed by context ID and action ID. Carries no version
/// or library metadata — the on-disk content is the state (see spec §5.3).
///
/// Phase 1.5: each action maps to an array of bindings (`[Shortcut]`). Phase 1
/// on-disk data wrote a single scalar `Shortcut`; the JSON/TOML decoders
/// transparently upgrade that legacy shape to a single-element array on read.
/// Library-owned user preferences, persisted alongside `overrides` through the
/// same `ShortcutBindingsStore`. A field is `nil` when the user hasn't diverged
/// from the app author's default, so the section is only written when customized
/// (mirroring how binding overrides are stored only when overridden).
public struct Preferences: Sendable, Equatable, Codable {
    /// User's hint-visibility choice, or `nil` to follow the app default.
    public var hintsEnabled: Bool?

    public init(hintsEnabled: Bool? = nil) {
        self.hintsEnabled = hintsEnabled
    }

    /// True when no preference diverges from its default (nothing to persist).
    public var isDefault: Bool { hintsEnabled == nil }
}

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
        // Only persist the preferences section when something diverges from default.
        if !preferences.isDefault {
            try container.encode(preferences, forKey: .preferences)
        }
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

// MARK: - Ergonomic accessors

public extension RawState {
    /// All context IDs with at least one persisted override, in unspecified order.
    var contextIDs: [String] { Array(overrides.keys) }

    /// All action IDs with persisted overrides in `contextID`, in unspecified order.
    /// Empty if the context has no overrides.
    func actionIDs(in contextID: String) -> [String] {
        overrides[contextID].map { Array($0.keys) } ?? []
    }

    /// Read or write the bindings for one action. Setting `nil` (or an empty array)
    /// removes the override; the surrounding context entry is pruned if it becomes
    /// empty so `overrides` stays canonical (no zombie empty dictionaries).
    ///
    /// Designed for `.custom` migrations and custom `ShortcutBindingsStore`s — the
    /// raw triple-nested `overrides` dictionary is still available, but this is
    /// the supported path.
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
    /// A readable, TOML-ish dump for bug reports and logging: each context, its
    /// overridden actions, and the binding display strings, plus any non-default
    /// preferences. Sorted for stable output.
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
    /// Remove all persisted ShortcutKit state. The default saves an empty
    /// `RawState` — for a namespaced `FileStore`, that clears the library's subtree
    /// while preserving sibling tables. Conformers with a cheaper wipe (e.g.
    /// `UserDefaultsStore`, which removes its key) override this.
    func clear() throws { try save(RawState()) }
}
