import Combine
import ShortcutKit
import SwiftUI

/// Consumes ShortcutKit's Core debug surface: the live activation stack, and the
/// outcome of the most recent keystroke.
///
/// Recording is driven by the view's lifetime, so the app pays nothing for the
/// debug path while this window is closed.
@MainActor
struct DebugWindowView: View {
    private let registry = ContextWiring.shared

    @State private var lastEvent: ShortcutDebugEvent?
    @State private var snapshot = ActivationSnapshot()
    @State private var bag: Set<AnyCancellable> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            activationStack
            Divider()
            lastEventLine
        }
        .padding()
        .frame(minWidth: 420, minHeight: 260, alignment: .topLeading)
        .onAppear {
            registry.isDebugRecording = true
            registry.debugEvents
                .sink { event in
                    lastEvent = event
                    snapshot = registry.activationSnapshot
                }
                .store(in: &bag)
            snapshot = registry.activationSnapshot
        }
        .onDisappear {
            registry.isDebugRecording = false
            bag.removeAll()
        }
    }

    private var activationStack: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Activation stack").font(.headline)
            if snapshot.isEmpty {
                Text("No active contexts — nothing is listening.")
                    .foregroundStyle(.secondary)
            } else {
                // Innermost first: the order dispatch consults, so the top row
                // is the one that wins a tie.
                ForEach(Array(snapshot.innermostFirst.enumerated()), id: \.element.id) { depth, entry in
                    HStack(spacing: 8) {
                        Text("\(depth)").monospacedDigit().foregroundStyle(.secondary)
                        Text(entry.displayName)
                        Text(entry.contextID).font(.caption).foregroundStyle(.secondary)
                        if entry.scope == .global {
                            Text("global").font(.caption).foregroundStyle(.orange)
                        }
                        Spacer()
                        Text(entry.activationID.uuidString.prefix(8))
                            .font(.caption.monospaced())
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }

    private var lastEventLine: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Last event").font(.headline)
            if let lastEvent {
                Text("\(lastEvent.pressed.displayString) → \(describe(lastEvent.outcome))")
                    .font(.body.monospaced())
            } else {
                Text("Press a key in the app window.").foregroundStyle(.secondary)
            }
        }
    }

    private func describe(_ outcome: ShortcutDebugEvent.Outcome) -> String {
        switch outcome {
        case let .dispatched(ref, depth):
            "dispatched \(ref.contextID).\(ref.actionID) (depth \(depth))"
        case let .advanced(ref):
            "chord in progress — \(ref.contextID).\(ref.actionID)"
        case let .suppressedKeyRepeat(ref):
            "suppressed key repeat — \(ref.contextID).\(ref.actionID)"
        case .noMatch:
            "no match (or surrendered to a focused text field)"
        }
    }
}
