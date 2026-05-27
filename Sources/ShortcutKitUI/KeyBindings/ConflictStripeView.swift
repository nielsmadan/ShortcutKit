import ShortcutKit
import SwiftUI

@MainActor
struct ConflictStripeView: View {
    let conflicts: [Conflict]
    var onJump: ((Occurrence) -> Void)?

    @State private var popoverShown = false

    init(conflicts: [Conflict], onJump: ((Occurrence) -> Void)? = nil) {
        self.conflicts = conflicts
        self.onJump = onJump
    }

    var body: some View {
        Rectangle()
            .fill(Self.color(for: conflicts))
            .frame(width: 3)
            .contentShape(Rectangle())
            .onTapGesture { if !conflicts.isEmpty { popoverShown.toggle() } }
            .popover(isPresented: $popoverShown) {
                ConflictPopover(conflicts: conflicts, onJump: onJump)
            }
    }

    static func color(for conflicts: [Conflict]) -> Color {
        if conflicts.isEmpty { return .clear }
        return conflicts.contains { $0.severity == .error } ? .red : .yellow
    }
}
