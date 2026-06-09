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
                Text(uiString("Duplicate binding")).bold()
                ForEach(occurrences, id: \.self) { occurrence in
                    jumpButton(occurrence.actionID, occurrence)
                }
            }
        case let .unreachablePrefix(blocker, blocked):
            VStack(alignment: .leading) {
                Text(uiString("Unreachable prefix")).bold()
                jumpButton(uiString("Blocker: \(blocker.actionID)"), blocker)
                jumpButton(uiString("Blocked: \(blocked.actionID)"), blocked)
            }
        case let .systemShared(action):
            VStack(alignment: .leading) {
                Text(uiString("System shortcut: \(action.shortcut.displayString)")).bold()
                jumpButton(action.actionID, action)
            }
        case let .menuCollision(action, menuItemTitle):
            VStack(alignment: .leading) {
                Text(uiString("Menu item collision: \(menuItemTitle)")).bold()
                jumpButton(action.actionID, action)
            }
        case let .shadowedByGlobal(local, global):
            VStack(alignment: .leading) {
                Text(uiString("Shadowed by global shortcut")).foregroundStyle(.red).bold()
                jumpButton(uiString("Local: \(local.actionID)"), local)
                jumpButton(uiString("Global: \(global.actionID)"), global)
            }
        case let .unsupportedInScope(occurrence, reason):
            VStack(alignment: .leading) {
                Text(uiString("Unsupported in scope")).foregroundStyle(.red).bold()
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
        case .multiStepInGlobal: uiString("Global shortcuts can't be chords")
        case .continuousInGlobal: uiString("Global shortcuts can't be continuous")
        }
    }
}
