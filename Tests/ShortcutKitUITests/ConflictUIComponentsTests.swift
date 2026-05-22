import ShortcutField
import ShortcutKit
@testable import ShortcutKitUI
import SwiftUI
import Testing

@MainActor
struct ConflictUIComponentsTests {
    @Test func stripeColorEmptyIsClear() {
        #expect(ConflictStripeView.color(for: []) == .clear)
    }

    @Test func stripeColorErrorIsRed() {
        let err = Conflict.duplicate(occurrences: [occ("a"), occ("b")]) // same-context dup is .error
        #expect(ConflictStripeView.color(for: [err]) == .red)
    }

    @Test func stripeColorWarningIsYellow() {
        let warn = Conflict.systemShared(shortcut: Shortcut("cmd+space"), action: occ("a"))
        #expect(ConflictStripeView.color(for: [warn]) == .yellow)
    }

    private func occ(_ id: String) -> Occurrence {
        Occurrence(contextID: "ctx", actionID: id, shortcut: Shortcut("cmd+s"))
    }
}
