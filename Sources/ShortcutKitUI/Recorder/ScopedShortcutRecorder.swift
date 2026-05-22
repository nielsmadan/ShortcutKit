import ShortcutField
import ShortcutKit
import SwiftUI

/// Wraps `ShortcutRecorderView` and refuses commits that violate the scope policy.
///
/// On rejection the underlying binding is not updated and an inline reason
/// message is shown below the recorder until the next valid commit clears it.
///
/// The wrapped recorder records `DiscreteShortcut` values; the umbrella
/// `Shortcut` binding is hydrated as `.discrete(...)` on commit. Continuous
/// shortcuts can only enter the binding from outside (e.g. existing persisted
/// state); the policy still rejects them in `.global` scope for symmetry with
/// `ConflictAnalyzer.detectUnsupportedInScope`.
@MainActor
public struct ScopedShortcutRecorder: View {
    @Binding var shortcut: Shortcut?
    let policy: ScopePolicy
    @State private var rejection: ScopePolicy.RejectReason?

    public init(shortcut: Binding<Shortcut?>, policy: ScopePolicy) {
        _shortcut = shortcut
        self.policy = policy
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ShortcutRecorderView(Binding<DiscreteShortcut?>(
                get: {
                    if case let .discrete(discrete) = shortcut { return discrete }
                    return nil
                },
                set: { newValue in
                    let candidate: Shortcut? = newValue.map { Shortcut.discrete($0) }
                    if let candidate, case let .reject(reason) = policy.validate(candidate) {
                        rejection = reason
                        return
                    }
                    rejection = nil
                    shortcut = candidate
                }
            ))
            .frame(width: 130)
            if let rejection {
                Text(rejection.userMessage)
                    .font(.caption2)
                    .foregroundStyle(.red)
            }
        }
    }
}

extension ScopePolicy.RejectReason {
    /// User-visible explanation shown below the recorder when a commit is refused.
    var userMessage: String {
        switch self {
        case .multiStepInGlobal: "Global shortcuts can't be chords"
        case .continuousInGlobal: "Global shortcuts can't be continuous"
        }
    }
}
