@testable import ShortcutKit
@testable import ShortcutKitUI
import SwiftUI
import Testing

@MainActor
struct ContextPickerViewTests {
    enum Act: String, ShortcutAction {
        case noop
        var definition: ShortcutActionDefinition { .init("Noop") }
    }

    private func ctx(_ id: String, scope: ContextScope = .local,
                     includeInSettings: Bool = true) -> ShortcutContext<Act>
    {
        let c = ShortcutContext<Act>(id, scope: scope) { _, _ in }
        c.includeInSettings = includeInSettings
        return c
    }

    @Test func segmentedForFewContexts() {
        let view = ContextPickerView(
            contexts: [ctx("a"), ctx("b")],
            selection: .constant("a"),
            conflictedIDs: []
        )
        #expect(view.pickerStyle == .segmented)
    }

    @Test func dropdownForManyContexts() {
        let ctxs = (1 ... 5).map { ctx("c\($0)") }
        let view = ContextPickerView(contexts: ctxs, selection: .constant("c1"), conflictedIDs: [])
        #expect(view.pickerStyle == .dropdown)
    }

    @Test func globalContextHasGlobeBadge() {
        let g = ctx("global", scope: .global)
        let view = ContextPickerView(contexts: [g], selection: .constant("global"), conflictedIDs: [])
        #expect(view.label(for: g).contains("🌐"))
    }

    @Test func excludesHiddenContexts() {
        let hidden = ctx("hidden", includeInSettings: false)
        let shown = ctx("shown")
        let view = ContextPickerView(contexts: [hidden, shown], selection: .constant("shown"), conflictedIDs: [])
        #expect(view.visibleContexts.map(\.id) == ["shown"])
    }
}
