import ShortcutField
@testable import ShortcutKit
@testable import ShortcutKitUI
import Testing

@MainActor
struct SearchFilterTests {
    private func row(_ actionID: String, _ name: String, shortcuts: [Shortcut] = []) -> KeyBindingsTable.Row {
        KeyBindingsTable.Row(
            contextID: "ctx", actionID: actionID, displayName: name,
            kind: .discrete, effectiveShortcuts: shortcuts,
            isCustomized: false, conflicts: []
        )
    }

    @Test func filtersByActionLabel() {
        let rows = [row("save", "Save"), row("new", "New")]
        #expect(SearchField.filter(rows, query: "sav").count == 1)
    }

    @Test func filtersByBindingDisplay() {
        let r = row("save", "Save", shortcuts: [Shortcut("cmd+s")])
        let result = SearchField.filter([r], query: "⌘")
        #expect(result.count == 1)
    }

    @Test func emptyQueryReturnsAll() {
        let rows = [row("save", "Save"), row("new", "New")]
        #expect(SearchField.filter(rows, query: "").count == 2)
    }

    @Test func caseInsensitive() {
        let rows = [row("save", "Save")]
        #expect(SearchField.filter(rows, query: "SAVE").count == 1)
    }
}
