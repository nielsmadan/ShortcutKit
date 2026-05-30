import Combine
import ShortcutKit
import SwiftUI

@MainActor
struct ActionToast: View {
    let registry: ShortcutRegistry
    @State private var current: String?

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Color.clear
            if let current {
                Text(current)
                    .padding(10)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
                    .padding()
                    .transition(.opacity)
                    .id(current) // re-trigger transition when text changes
            }
        }
        .allowsHitTesting(false)
        .onReceive(registry.actionFired) { event in
            let label = labelFor(event: event)
            let via = event.source == .shortcut
                ? rowFor(event)?.effectiveShortcuts.first?.displayString ?? "shortcut"
                : "(button)"
            let text = "\(label) — via \(via)"
            current = text
            let snapshot = text
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                if current == snapshot { current = nil }
            }
        }
    }

    private func labelFor(event: ActionFiredEvent) -> String {
        if let displayName = rowFor(event)?.displayName {
            return String(localized: displayName)
        }
        return event.actionID
    }

    private func rowFor(_ event: ActionFiredEvent) -> KeyBindings.Entry? {
        for group in registry.keyBindings.groups where group.contextID == event.contextID {
            return group.entries.first(where: { $0.actionID == event.actionID })
        }
        return nil
    }
}
