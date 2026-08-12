@testable import ShortcutKitUI
import Testing

@MainActor
struct KeyBindingsStyleTests {
    @Test func styleEnumHasTwoCases() {
        let allCases: [KeyBindingsStyle] = [.regular, .dense]
        #expect(allCases.count == 2)
    }
}
