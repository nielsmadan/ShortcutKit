import ShortcutField
import ShortcutKit

enum ScopePolicy: Sendable, Hashable {
    case local
    case global

    enum Validation: Sendable, Equatable {
        case accept
        case reject(reason: RejectReason)
    }

    enum RejectReason: Sendable, Equatable {
        case multiStepInGlobal
        case continuousInGlobal
    }

    init(_ scope: ContextScope) {
        switch scope {
        case .local: self = .local
        case .global: self = .global
        }
    }

    func validate(_ shortcut: Shortcut) -> Validation {
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
