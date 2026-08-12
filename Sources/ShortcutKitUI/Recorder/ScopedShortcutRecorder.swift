import ShortcutField
import ShortcutKit
import SwiftUI

@MainActor
struct ScopedShortcutRecorder: View {
    @Binding var shortcut: Shortcut?
    let policy: ScopePolicy
    let style: KeyBindingsStyle
    @State private var rejection: ScopePolicy.RejectReason?

    // ShortcutField needs both its minimum and SwiftUI frame constrained.
    static let discreteWidth: (regular: CGFloat, dense: CGFloat) = (110, 85)
    static let continuousWidth: (regular: CGFloat, dense: CGFloat) = (130, 100)

    private var fieldWidth: CGFloat {
        style == .dense ? Self.discreteWidth.dense : Self.discreteWidth.regular
    }

    private var continuousFieldWidth: CGFloat {
        style == .dense ? Self.continuousWidth.dense : Self.continuousWidth.regular
    }

    init(shortcut: Binding<Shortcut?>, policy: ScopePolicy, style: KeyBindingsStyle = .regular) {
        _shortcut = shortcut
        self.policy = policy
        self.style = style
    }

    var body: some View {
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
    var userMessage: String {
        switch self {
        case .multiStepInGlobal: "Global shortcuts can't be chords"
        case .continuousInGlobal: "Global shortcuts can't be continuous"
        }
    }
}
