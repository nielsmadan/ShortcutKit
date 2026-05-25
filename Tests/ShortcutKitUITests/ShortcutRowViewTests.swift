import ShortcutField
@testable import ShortcutKit
@testable import ShortcutKitUI
import Testing

@MainActor
struct ShortcutRowViewTests {
    @Test func bindingCountReflectsRow() {
        let row = KeyBindingsTable.Row(
            contextID: "editor",
            actionID: "save",
            displayName: "Save",
            kind: .discrete,
            effectiveShortcuts: [Shortcut("cmd+s"), Shortcut("ctrl+s")],
            isCustomized: false,
            conflicts: []
        )
        let view = ShortcutRowView(
            row: row,
            policy: .local,
            onSet: { _ in }, onClear: { _ in }, onReset: {}
        )
        #expect(view.bindingCount == 2)
    }

    @Test func onSetReceivesUpdatedArray() {
        let row = KeyBindingsTable.Row(
            contextID: "editor", actionID: "save", displayName: "Save",
            kind: .discrete, effectiveShortcuts: [Shortcut("cmd+s")],
            isCustomized: true, conflicts: []
        )
        var received: [Shortcut]?
        let view = ShortcutRowView(
            row: row, policy: .local,
            onSet: { received = $0 }, onClear: { _ in }, onReset: {}
        )
        view.appendEmptyBinding()
        #expect(received?.count == 2)
        #expect(received?.first == Shortcut("cmd+s"))
    }
}
