import ShortcutField

/// A detected conflict between two or more bindings.
public enum Conflict: Sendable, Hashable {
    case duplicate(occurrences: [Occurrence])
    case unreachablePrefix(blocker: Occurrence, blocked: Occurrence)
    case systemShared(action: Occurrence)
    /// `menuItemTitle` is the menu item's already-resolved *displayed* title at
    /// detection time (AppKit titles are localized/runtime values), for surfacing
    /// in conflict UI — not a stable identifier.
    case menuCollision(action: Occurrence, menuItemTitle: String)
    case shadowedByGlobal(local: Occurrence, global: Occurrence)
    case unsupportedInScope(occurrence: Occurrence, reason: UnsupportedReason)

    /// Why a binding is unsupported in its declared scope.
    public enum UnsupportedReason: Sendable, Hashable {
        case multiStepInGlobal
        case continuousInGlobal
    }

    /// Conflict severity ordered from `warning` to `error`.
    public enum Severity: Sendable, Hashable, Comparable {
        case warning
        case error
    }

    /// Severity rule: within-context `duplicate` / `unreachablePrefix` are
    /// `.error`; cross-context variants, `systemShared`, and `menuCollision`
    /// are `.warning`. `shadowedByGlobal` and `unsupportedInScope` are `.error`.
    public var severity: Severity {
        switch self {
        case let .duplicate(occurrences):
            let contexts = Set(occurrences.map(\.contextID))
            return contexts.count == 1 ? .error : .warning
        case let .unreachablePrefix(blocker, blocked):
            return blocker.contextID == blocked.contextID ? .error : .warning
        case .shadowedByGlobal, .unsupportedInScope:
            return .error
        case .systemShared, .menuCollision:
            return .warning
        }
    }
}

public extension Conflict {
    /// Every binding occurrence involved in the conflict.
    var occurrences: [Occurrence] {
        switch self {
        case let .duplicate(occurrences):
            occurrences
        case let .unreachablePrefix(blocker, blocked):
            [blocker, blocked]
        case let .systemShared(action):
            [action]
        case let .menuCollision(action, _):
            [action]
        case let .shadowedByGlobal(local, global):
            [local, global]
        case let .unsupportedInScope(occurrence, _):
            [occurrence]
        }
    }
}

/// A context, action, and shortcut involved in a conflict.
public struct Occurrence: Sendable, Hashable {
    public let contextID: String
    public let actionID: String
    public let shortcut: Shortcut
    public init(contextID: String, actionID: String, shortcut: Shortcut) {
        self.contextID = contextID
        self.actionID = actionID
        self.shortcut = shortcut
    }
}
