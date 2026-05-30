import ShortcutField
import ShortcutKit
import SwiftUI

/// A single row in the bindings table.
///
/// Layout: label + `Spacer()` + N `ScopedShortcutRecorder`s (one per existing
/// binding) + per-binding clear (`xmark.circle`) + optional add (`plus`) +
/// per-row reset (`arrow.uturn.backward`).
///
/// The leading stripe is a thin colored bar reflecting the worst conflict
/// severity on this row. T11 replaces this placeholder with the real
/// `ConflictStripeView` (popover-on-tap behavior).
@MainActor
struct ShortcutRowView: View {
    let row: KeyBindings.Entry
    let policy: ScopePolicy
    let onSet: ([Shortcut]) -> Void
    let onClear: (Int) -> Void
    let onReset: () -> Void
    let onJump: ((Occurrence) -> Void)?

    @Environment(\.shortcutStyle) private var style

    init(
        row: KeyBindings.Entry,
        policy: ScopePolicy,
        onSet: @escaping ([Shortcut]) -> Void,
        onClear: @escaping (Int) -> Void,
        onReset: @escaping () -> Void,
        onJump: ((Occurrence) -> Void)? = nil
    ) {
        self.row = row
        self.policy = policy
        self.onSet = onSet
        self.onClear = onClear
        self.onReset = onReset
        self.onJump = onJump
    }

    var body: some View {
        HStack(spacing: style == .dense ? 8 : 10) {
            ConflictStripeView(conflicts: row.conflicts, onJump: onJump)
                .frame(width: 3)
            Text(row.displayName)
                .font(.system(size: style == .dense ? 11 : 13))
                .lineLimit(1)
            Spacer(minLength: 8)
            recorders
            resetButton
        }
        .padding(.vertical, style == .dense ? 1 : 10)
    }

    // MARK: - Testable internals

    var bindingCount: Int { row.effectiveShortcuts.count }

    /// Test hook: appends a placeholder binding slot via `onSet`. The placeholder
    /// shortcut is arbitrary — production callers replace it via the recorder.
    /// `Shortcut("")` would trap (empty ascii throws), so `space` is used as a
    /// parseable, harmless sentinel.
    func appendEmptyBinding() {
        onSet(row.effectiveShortcuts + [Shortcut("space")])
    }

    // MARK: - Sub-views

    @ViewBuilder
    private var recorders: some View {
        if style == .dense {
            // Two fixed slots: primary + alternative. Empty slot lets the
            // user record an alternative on the same row.
            ScopedShortcutRecorder(shortcut: slotBinding(at: 0), policy: policy)
            ScopedShortcutRecorder(shortcut: slotBinding(at: 1), policy: policy)
        } else {
            ForEach(Array(row.effectiveShortcuts.enumerated()), id: \.offset) { idx, shortcut in
                ScopedShortcutRecorder(
                    shortcut: binding(for: idx, current: shortcut),
                    policy: policy
                )
            }
        }
    }

    private var resetButton: some View {
        Button { onReset() } label: { Image(systemName: "arrow.uturn.backward") }
            .buttonStyle(.plain)
            .opacity(row.isCustomized ? 1 : 0)
    }

    /// Binding for a fixed-position recorder slot — used by the dense layout
    /// where each row always shows Primary + Alternative columns. Reading
    /// returns the binding at `idx` or `nil` if the row has fewer bindings;
    /// writing appends or replaces and trims an empty Alternative back to
    /// just a Primary.
    private func slotBinding(at idx: Int) -> Binding<Shortcut?> {
        Binding(
            get: {
                idx < row.effectiveShortcuts.count ? row.effectiveShortcuts[idx] : nil
            },
            set: { new in
                var copy = row.effectiveShortcuts
                if let new {
                    if idx < copy.count { copy[idx] = new } else {
                        while copy.count < idx {
                            copy.append(new)
                        }
                        copy.append(new)
                    }
                    onSet(copy)
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
