import ShortcutKit
import SwiftUI

@MainActor
public struct ConflictStripeView: View {
    public let conflicts: [Conflict]
    public var onJump: ((Occurrence) -> Void)?

    @State private var popoverShown = false

    public init(conflicts: [Conflict], onJump: ((Occurrence) -> Void)? = nil) {
        self.conflicts = conflicts
        self.onJump = onJump
    }

    public var body: some View {
        Rectangle()
            .fill(Self.color(for: conflicts))
            .frame(width: 3)
            .contentShape(Rectangle())
            .onTapGesture { if !conflicts.isEmpty { popoverShown.toggle() } }
            .popover(isPresented: $popoverShown) {
                ConflictPopover(conflicts: conflicts, onJump: onJump)
            }
    }

    /// Public for testability — colour for the stripe given a row's conflicts.
    public static func color(for conflicts: [Conflict]) -> Color {
        if conflicts.isEmpty { return .clear }
        return conflicts.contains { $0.severity == .error } ? .red : .yellow
    }
}
