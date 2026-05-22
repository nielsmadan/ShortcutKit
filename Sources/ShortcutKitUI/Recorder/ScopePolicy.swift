import ShortcutField
import ShortcutKit

/// UI-side gate that mirrors `ConflictAnalyzer.detectUnsupportedInScope`.
///
/// `ScopedShortcutRecorder` consults this policy before committing a candidate
/// binding so the violation is refused inline rather than surfacing later as a
/// `.unsupportedInScope` conflict. The same gates run at the data layer — defense
/// in depth: if a violating shortcut sneaks in via persistence or migration it
/// still gets flagged at runtime.
public enum ScopePolicy: Sendable, Hashable {
    case local
    case global

    public enum Validation: Sendable, Equatable {
        case accept
        case reject(reason: RejectReason)
    }

    public enum RejectReason: Sendable, Equatable {
        case multiStepInGlobal
        case continuousInGlobal
    }

    /// Bridges `ContextScope` from Core into a UI-side policy.
    public init(_ scope: ContextScope) {
        switch scope {
        case .local: self = .local
        case .global: self = .global
        }
    }

    public func validate(_ shortcut: Shortcut) -> Validation {
        switch self {
        case .local:
            return .accept
        case .global:
            switch shortcut {
            case let .discrete(discrete):
                if discrete.steps.count > 1 {
                    return .reject(reason: .multiStepInGlobal)
                }
                return .accept
            case .continuous:
                return .reject(reason: .continuousInGlobal)
            }
        }
    }
}
