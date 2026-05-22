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
public struct ShortcutRowView: View {
    public let row: KeyBindingsTable.Row
    public let policy: ScopePolicy
    public let bindingsPerAction: BindingsPerAction
    public let onSet: ([Shortcut]) -> Void
    public let onClear: (Int) -> Void
    public let onReset: () -> Void
    public let onJump: ((Occurrence) -> Void)?

    @Environment(\.shortcutStyle) private var style

    public init(
        row: KeyBindingsTable.Row,
        policy: ScopePolicy,
        bindingsPerAction: BindingsPerAction,
        onSet: @escaping ([Shortcut]) -> Void,
        onClear: @escaping (Int) -> Void,
        onReset: @escaping () -> Void,
        onJump: ((Occurrence) -> Void)? = nil
    ) {
        self.row = row
        self.policy = policy
        self.bindingsPerAction = bindingsPerAction
        self.onSet = onSet
        self.onClear = onClear
        self.onReset = onReset
        self.onJump = onJump
    }

    public var body: some View {
        HStack(spacing: 8) {
            ConflictStripeView(conflicts: row.conflicts, onJump: onJump)
            Text(row.displayName)
            Spacer()
            recorders
            if canAddMore { addButton }
            resetButton
        }
        .padding(.vertical, style == .dense ? 2 : 6)
    }

    // MARK: - Testable internals

    var bindingCount: Int { row.effectiveShortcuts.count }

    var canAddMore: Bool {
        switch bindingsPerAction {
        case .one: row.effectiveShortcuts.count < 1
        case .two: row.effectiveShortcuts.count < 2
        case .unlimited: true
        }
    }

    /// Test hook: appends a placeholder binding slot via `onSet`. The placeholder
    /// shortcut is arbitrary — production callers replace it via the recorder.
    /// `Shortcut("")` would trap (empty ascii throws), so `space` is used as a
    /// parseable, harmless sentinel until T14 wires up the real "click + then
    /// record" flow.
    func appendEmptyBinding() {
        guard canAddMore else { return }
        onSet(row.effectiveShortcuts + [Shortcut("space")])
    }

    // MARK: - Sub-views

    @ViewBuilder
    private var recorders: some View {
        ForEach(Array(row.effectiveShortcuts.enumerated()), id: \.offset) { idx, shortcut in
            HStack(spacing: 2) {
                ScopedShortcutRecorder(
                    shortcut: binding(for: idx, current: shortcut),
                    policy: policy
                )
                Button { onClear(idx) } label: { Image(systemName: "xmark.circle") }
                    .buttonStyle(.plain)
            }
        }
    }

    private var addButton: some View {
        Button { appendEmptyBinding() } label: { Image(systemName: "plus") }
            .buttonStyle(.plain)
    }

    private var resetButton: some View {
        Button { onReset() } label: { Image(systemName: "arrow.uturn.backward") }
            .buttonStyle(.plain)
            .opacity(row.isCustomized ? 1 : 0)
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
