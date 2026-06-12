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

    /// `.warning < .error`, so adopters can `conflicts.map(\.severity).max()`
    /// to find the worst severity in a set.
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
    /// Walks the `Occurrence`s referenced by this conflict, regardless of
    /// associated-value shape. Used by callers (e.g. `KeyBindingsView`) that
    /// need to map conflicts back to context IDs.
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

/// One occurrence in a conflict — a (context, action, shortcut) triple.
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
