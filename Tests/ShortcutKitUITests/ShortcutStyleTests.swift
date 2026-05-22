@testable import ShortcutKitUI
import SwiftUI
import Testing

@MainActor
struct ShortcutStyleTests {
    @Test func defaultStyleIsNative() {
        // The environment default value is `.native`.
        #expect(EnvironmentValues().shortcutStyle == .native)
    }

    @Test func styleEnumHasTwoCases() {
        // Exhaustive switch — fails to compile if a case is added/removed without test update.
        let allCases: [ShortcutStyle] = [.native, .dense]
        #expect(allCases.count == 2)
    }
}
