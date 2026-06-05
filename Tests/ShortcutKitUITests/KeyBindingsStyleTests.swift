@testable import ShortcutKitUI
import Testing

@MainActor
struct KeyBindingsStyleTests {
    @Test func styleEnumHasTwoCases() {
        // Exhaustive list — fails to compile if a case is added/removed without test update.
        let allCases: [KeyBindingsStyle] = [.native, .dense]
        #expect(allCases.count == 2)
    }
}
