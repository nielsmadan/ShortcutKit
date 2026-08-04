import Foundation
import ShortcutField
@testable import ShortcutKit
@testable import ShortcutKitUI
import Testing

@MainActor
struct ShortcutRowViewTests {
    @Test func bindingCountReflectsRow() {
        let row = KeyBindings.Entry(
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
            policy: .local, style: .regular,
            onSet: { _ in }, onClear: { _ in }, onReset: {}
        )
        #expect(view.bindingCount == 2)
    }

    @Test func onSetReceivesUpdatedArray() {
        let row = KeyBindings.Entry(
            contextID: "editor", actionID: "save", displayName: "Save",
            kind: .discrete, effectiveShortcuts: [Shortcut("cmd+s")],
            isCustomized: true, conflicts: []
        )
        var received: [Shortcut]?
        let view = ShortcutRowView(
            row: row, policy: .local, style: .regular,
            onSet: { received = $0 }, onClear: { _ in }, onReset: {}
        )
        view.appendEmptyBinding()
        #expect(received?.count == 2)
        #expect(received?.first == Shortcut("cmd+s"))
    }

    private func entry(description: LocalizedStringResource?) -> KeyBindings.Entry {
        KeyBindings.Entry(
            contextID: "editor", actionID: "save", displayName: "Save",
            description: description, kind: .discrete,
            effectiveShortcuts: [Shortcut("cmd+s")], isCustomized: false, conflicts: []
        )
    }

    private func row(_ description: LocalizedStringResource?, showsDescription: Bool) -> ShortcutRowView {
        ShortcutRowView(
            row: entry(description: description), policy: .local, style: .regular,
            showsDescription: showsDescription,
            onSet: { _ in }, onClear: { _ in }, onReset: {}
        )
    }

    @Test func subtitleSuppressedWhenFlagOff() {
        #expect(row("Saves the file", showsDescription: false).subtitleText == nil)
    }

    @Test func subtitleNilWhenNoDescription() {
        #expect(row(nil, showsDescription: true).subtitleText == nil)
    }

    @Test func subtitleShownWhenFlagOnAndDescriptionPresent() {
        #expect(row("Saves the file", showsDescription: true).subtitleText == "Saves the file")
    }
}
