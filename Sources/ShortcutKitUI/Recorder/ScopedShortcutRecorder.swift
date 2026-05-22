import ShortcutField
import ShortcutKit
import SwiftUI

/// Wraps the appropriate ShortcutField recorder for the bound shortcut's kind
/// and refuses commits that violate the scope policy.
///
/// - Discrete shortcuts (and empty state) render `ShortcutRecorderView`.
/// - Continuous shortcuts render `ContinuousShortcutRecorderView`, which
///   includes a sensitivity slider.
///
/// On rejection (scope policy violation) the underlying binding is not updated
/// and an inline reason message is shown until the next valid commit clears it.
@MainActor
public struct ScopedShortcutRecorder: View {
    @Binding var shortcut: Shortcut?
    let policy: ScopePolicy
    @Environment(\.shortcutStyle) private var style
    @State private var rejection: ScopePolicy.RejectReason?

    /// Width of the embedded recorder field. Smaller in `.dense` so two
    /// recorders side-by-side don't push labels off the row. These widths
    /// are also pushed down into ShortcutField's `.minimumWidth(_:)` so the
    /// underlying NSSearchField actually honors them (without that, the
    /// AppKit view renders at its intrinsic placeholder width and overflows
    /// into the next column).
    static let discreteWidth: (native: CGFloat, dense: CGFloat) = (110, 85)
    static let continuousWidth: (native: CGFloat, dense: CGFloat) = (130, 100)

    private var fieldWidth: CGFloat {
        style == .dense ? Self.discreteWidth.dense : Self.discreteWidth.native
    }

    private var continuousFieldWidth: CGFloat {
        style == .dense ? Self.continuousWidth.dense : Self.continuousWidth.native
    }

    public init(shortcut: Binding<Shortcut?>, policy: ScopePolicy) {
        _shortcut = shortcut
        self.policy = policy
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            switch shortcut {
            case let .continuous(continuous):
                continuousRecorder(initial: continuous)
            case .discrete, nil:
                discreteRecorder
            }
            if let rejection {
                Text(rejection.userMessage)
                    .font(.caption2)
                    .foregroundStyle(.red)
            }
        }
    }

    private var discreteRecorder: some View {
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
        .placeholder(style == .dense ? "Record" : "Record Shortcut")
        .minimumWidth(fieldWidth)
        .frame(width: fieldWidth)
    }

    private func continuousRecorder(initial: ContinuousShortcut) -> some View {
        ContinuousShortcutRecorderView(Binding<ContinuousShortcut?>(
            get: {
                if case let .continuous(continuous) = shortcut { return continuous }
                return initial
            },
            set: { newValue in
                let candidate: Shortcut? = newValue.map { Shortcut.continuous($0) }
                if let candidate, case let .reject(reason) = policy.validate(candidate) {
                    rejection = reason
                    return
                }
                rejection = nil
                shortcut = candidate
            }
        ))
        .frame(width: continuousFieldWidth)
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
