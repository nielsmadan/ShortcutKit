import ShortcutField
import ShortcutKit
import SwiftUI

@MainActor
struct ShortcutRowView: View {
    let row: KeyBindings.Entry
    let policy: ScopePolicy
    let style: KeyBindingsStyle
    let showsDescription: Bool
    let onSet: ([Shortcut]) -> Void
    let onClear: (Int) -> Void
    let onReset: () -> Void
    let onJump: ((Occurrence) -> Void)?

    init(
        row: KeyBindings.Entry,
        policy: ScopePolicy,
        style: KeyBindingsStyle,
        showsDescription: Bool = false,
        onSet: @escaping ([Shortcut]) -> Void,
        onClear: @escaping (Int) -> Void,
        onReset: @escaping () -> Void,
        onJump: ((Occurrence) -> Void)? = nil
    ) {
        self.row = row
        self.policy = policy
        self.style = style
        self.showsDescription = showsDescription
        self.onSet = onSet
        self.onClear = onClear
        self.onReset = onReset
        self.onJump = onJump
    }

    var body: some View {
        HStack(spacing: style == .dense ? 8 : 10) {
            ConflictStripeView(conflicts: row.conflicts, onJump: onJump)
                .frame(width: 3)
            VStack(alignment: .leading, spacing: 1) {
                Text(row.displayName)
                    .font(.system(size: style == .dense ? 11 : 13))
                    .lineLimit(1)
                if showsDescription, let description = row.description {
                    Text(description)
                        .font(.system(size: style == .dense ? 9 : 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            recorders
            resetButton
        }
        .padding(.vertical, style == .dense ? 1 : 10)
    }

    var bindingCount: Int { row.effectiveShortcuts.count }

    var subtitleText: String? {
        guard showsDescription, let description = row.description else { return nil }
        return String(localized: description)
    }

    func appendEmptyBinding() {
        onSet(row.effectiveShortcuts + [Shortcut("space")])
    }

    // MARK: - Sub-views

    @ViewBuilder
    private var recorders: some View {
        if style == .dense {
            ScopedShortcutRecorder(shortcut: slotBinding(at: 0), policy: policy, style: style)
            ScopedShortcutRecorder(shortcut: slotBinding(at: 1), policy: policy, style: style)
                .disabled(row.effectiveShortcuts.isEmpty)
        } else {
            ForEach(Array(row.effectiveShortcuts.enumerated()), id: \.offset) { idx, shortcut in
                ScopedShortcutRecorder(
                    shortcut: binding(for: idx, current: shortcut),
                    policy: policy,
                    style: style
                )
            }
        }
    }

    private var resetButton: some View {
        Button { onReset() } label: { Image(systemName: "arrow.uturn.backward") }
            .buttonStyle(.plain)
            .opacity(row.isCustomized ? 1 : 0)
    }

    private func slotBinding(at idx: Int) -> Binding<Shortcut?> {
        Binding(
            get: {
                idx < row.effectiveShortcuts.count ? row.effectiveShortcuts[idx] : nil
            },
            set: { new in
                let copy = row.effectiveShortcuts
                if let new {
                    guard let updated = settingShortcut(new, at: idx, in: copy) else { return }
                    onSet(updated)
                } else if idx < copy.count {
                    onClear(idx)
                }
            }
        )
    }

    private func binding(for idx: Int, current: Shortcut) -> Binding<Shortcut?> {
        Binding(
            get: { current },
            set: { new in
                guard let new else {
                    onClear(idx)
                    return
                }
                var copy = row.effectiveShortcuts
                copy[idx] = new
                onSet(copy)
            }
        )
    }
}

func settingShortcut(_ shortcut: Shortcut, at index: Int, in shortcuts: [Shortcut]) -> [Shortcut]? {
    guard index >= 0, index <= shortcuts.count else { return nil }
    var updated = shortcuts
    if index == updated.count {
        updated.append(shortcut)
    } else {
        updated[index] = shortcut
    }
    return updated
}
