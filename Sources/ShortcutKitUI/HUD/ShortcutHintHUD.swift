import Combine
import ShortcutKit
import SwiftUI

/// View modifier backing `View.shortcutHintHUD(registry:policy:)`. Observes a
/// registry's `actionFired` publisher and surfaces a transient
/// "Tip: <action> is bound to <shortcut>" overlay when an action fires via a
/// non-shortcut path AND has at least one effective binding.
///
/// Suppression is governed by:
///   - `HintPolicy` (developer-set upper bound on frequency)
///   - `registry.hintsEnabled` (the user preference, persisted through the
///     registry's store; default from `ShortcutRegistry(defaultHintsEnabled:)`)
@MainActor
struct ShortcutHintHUD: ViewModifier {
    @ObservedObject var registry: ShortcutRegistry
    let policy: HintPolicy

    @State private var gate: HintPolicyGate
    @State private var current: String?

    init(registry: ShortcutRegistry, policy: HintPolicy = .oncePerSession) {
        self.registry = registry
        self.policy = policy
        _gate = State(initialValue: HintPolicyGate(policy: policy))
    }

    func body(content: Content) -> some View {
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
        guard registry.hintsEnabled, event.source == .programmatic else { return }
        guard let entry = entryFor(event: event),
              let firstBinding = entry.effectiveShortcuts.first
        else { return }
        guard gate.shouldShow(actionID: event.actionID) else { return }
        gate.markShown(actionID: event.actionID)
        let name = String(localized: entry.displayName)
        let shortcut = firstBinding.displayString
        // Localizable template — translators get "Tip: %@ is bound to %@".
        let text = String(localized: "Tip: \(name) is bound to \(shortcut)")
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

    private func entryFor(event: ActionFiredEvent) -> KeyBindings.Entry? {
        for group in registry.keyBindings.groups where group.contextID == event.contextID {
            return group.entries.first(where: { $0.actionID == event.actionID })
        }
        return nil
    }
}

public extension View {
    /// Attach the discoverability HUD to this view. Gated by `registry.hintsEnabled`
    /// (the user preference, persisted through the registry's store); `policy` is
    /// the developer-set upper bound on frequency.
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
