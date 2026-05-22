import Combine
import ShortcutKit
import SwiftUI

/// View modifier that observes a registry's `actionFired` publisher and surfaces a
/// transient "Tip: <action> is bound to <shortcut>" overlay when an action fires via
/// a non-shortcut path AND has at least one effective binding.
///
/// Suppression is governed by:
///   - `HintPolicy` (developer-set upper bound on frequency)
///   - `@AppStorage("shortcutkit.hintsEnabled")` (user-set runtime gate, default `true`)
@MainActor
public struct ShortcutHintHUD: ViewModifier {
    public let registry: ShortcutRegistry
    public let policy: HintPolicy

    @AppStorage("shortcutkit.hintsEnabled") private var hintsEnabled = true
    @State private var gate: HintPolicyGate
    @State private var current: String?

    public init(registry: ShortcutRegistry, policy: HintPolicy = .oncePerSession) {
        self.registry = registry
        self.policy = policy
        _gate = State(initialValue: HintPolicyGate(policy: policy))
    }

    public func body(content: Content) -> some View {
        content
            .overlay(alignment: .topTrailing) {
                if let current {
                    HintToast(text: current)
                        .padding()
                        .transition(.opacity)
                }
            }
            .onReceive(registry.actionFired) { event in
                handle(event: event)
            }
    }

    private func handle(event: ActionFiredEvent) {
        guard hintsEnabled, !event.viaShortcut else { return }
        guard let row = rowFor(event: event),
              let firstBinding = row.effectiveShortcuts.first
        else { return }
        guard gate.shouldShow(actionID: event.actionID) else { return }
        gate.markShown(actionID: event.actionID)
        let text = "Tip: \(row.displayName) is bound to \(firstBinding.displayString)"
        current = text
        Task {
            try? await Task.sleep(for: .seconds(2))
            // Guard ensures the timer doesn't clear a newer hint that has since
            // replaced the one we set.
            if current == text {
                current = nil
            }
        }
    }

    private func rowFor(event: ActionFiredEvent) -> KeyBindingsTable.Row? {
        let table = registry.keyBindingsTable
        for section in table.sections where section.contextID == event.contextID {
            return section.rows.first(where: { $0.actionID == event.actionID })
        }
        return nil
    }
}

public extension View {
    /// Attach the discoverability HUD to this view. Reads `@AppStorage("shortcutkit.hintsEnabled")`
    /// as the user-facing gate (default true). The policy is the developer-set upper bound.
    func shortcutHintHUD(
        registry: ShortcutRegistry,
        policy: HintPolicy = .oncePerSession
    ) -> some View {
        modifier(ShortcutHintHUD(registry: registry, policy: policy))
    }
}

private struct HintToast: View {
    let text: String
    var body: some View {
        Text(text)
            .padding(8)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}
