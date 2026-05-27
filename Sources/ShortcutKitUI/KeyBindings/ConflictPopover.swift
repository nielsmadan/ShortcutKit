import ShortcutField
import ShortcutKit
import SwiftUI

@MainActor
struct ConflictPopover: View {
    let conflicts: [Conflict]
    var onJump: ((Occurrence) -> Void)?

    init(conflicts: [Conflict], onJump: ((Occurrence) -> Void)? = nil) {
        self.conflicts = conflicts
        self.onJump = onJump
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(conflicts.enumerated()), id: \.offset) { _, conflict in
                ConflictRow(conflict: conflict, onJump: onJump)
            }
        }
        .padding(12)
        .frame(minWidth: 240)
    }
}

private struct ConflictRow: View {
    let conflict: Conflict
    let onJump: ((Occurrence) -> Void)?

    var body: some View {
        switch conflict {
        case let .duplicate(occurrences):
            VStack(alignment: .leading) {
                Text("Duplicate binding").bold()
                ForEach(occurrences, id: \.self) { occurrence in
                    jumpButton(occurrence.actionID, occurrence)
                }
            }
        case let .unreachablePrefix(blocker, blocked):
            VStack(alignment: .leading) {
                Text("Unreachable prefix").bold()
                jumpButton("Blocker: \(blocker.actionID)", blocker)
                jumpButton("Blocked: \(blocked.actionID)", blocked)
            }
        case let .systemShared(shortcut, action):
            VStack(alignment: .leading) {
                Text("System shortcut: \(shortcut.displayString)").bold()
                jumpButton(action.actionID, action)
            }
        case let .menuCollision(_, action, menuItemTitle):
            VStack(alignment: .leading) {
                Text("Menu item collision: \(menuItemTitle)").bold()
                jumpButton(action.actionID, action)
            }
        case let .shadowedByGlobal(local, global):
            VStack(alignment: .leading) {
                Text("Shadowed by global shortcut").foregroundStyle(.red).bold()
                jumpButton("Local: \(local.actionID)", local)
                jumpButton("Global: \(global.actionID)", global)
            }
        case let .unsupportedInScope(occurrence, reason):
            VStack(alignment: .leading) {
                Text("Unsupported in scope").foregroundStyle(.red).bold()
                Text(describe(reason)).font(.caption)
                jumpButton(occurrence.actionID, occurrence)
            }
        }
    }

    private func jumpButton(_ label: String, _ occurrence: Occurrence) -> some View {
        Button(label) { onJump?(occurrence) }.buttonStyle(.link)
    }

    private func describe(_ reason: Conflict.UnsupportedReason) -> String {
        switch reason {
        case .multiStepInGlobal: "Global shortcuts can't be chords"
        case .continuousInGlobal: "Global shortcuts can't be continuous"
        }
    }
}
