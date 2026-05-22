import ShortcutField

/// A detected conflict between two or more bindings.
public enum Conflict: Sendable, Hashable {
    case duplicate(occurrences: [Occurrence])
    case unreachablePrefix(blocker: Occurrence, blocked: Occurrence)
    case systemShared(shortcut: Shortcut, action: Occurrence)
    case menuCollision(shortcut: Shortcut, action: Occurrence, menuItemTitle: String)
    case shadowedByGlobal(local: Occurrence, global: Occurrence)
    case unsupportedInScope(occurrence: Occurrence, reason: UnsupportedReason)

    /// Why a binding is unsupported in its declared scope.
    public enum UnsupportedReason: Sendable, Hashable {
        case multiStepInGlobal
        case continuousInGlobal
    }

    public enum Severity: Sendable { case error, warning }

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
