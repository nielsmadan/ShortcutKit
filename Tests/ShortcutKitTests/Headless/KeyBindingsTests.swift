import Foundation
import ShortcutField
@testable import ShortcutKit
import Testing

enum TableAct: String, ShortcutAction {
    case save, undo, zoom
    var definition: ShortcutActionDefinition {
        switch self {
        case .save: .init("Save File", "cmd+s")
        case .undo: .init("Undo Change", "cmd+z")
        case .zoom: .init("Zoom", "cmd+pinch-out @0.5")
        }
    }
}

@MainActor
@Suite("KeyBindings") struct KeyBindingsTests {
    private func isolatedStore() -> UserDefaultsStore {
        let suite = "ShortcutKitTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return UserDefaultsStore(defaults: defaults)
    }

    @Test("table has one section per context with one row per action")
    func tableShape() {
        let ctx = ShortcutContext<TableAct>("editor")
        let registry = ShortcutRegistry(contexts: [ctx], store: isolatedStore())
        let table = registry.keyBindings
        #expect(table.groups.count == 1)
        #expect(table.groups[0].contextID == "editor")
        #expect(table.groups[0].entries.map(\.actionID).sorted() == ["save", "undo", "zoom"])
    }

    @Test("rows carry displayName, kind, effectiveShortcuts, isCustomized")
    func rowFields() {
        let ctx = ShortcutContext<TableAct>("editor")
        let registry = ShortcutRegistry(contexts: [ctx], store: isolatedStore())
        registry.setShortcuts(["cmd+shift+s"], contextID: "editor", actionID: "save")
        let table = registry.keyBindings
        let save = table.groups[0].entries.first { $0.actionID == "save" }!
        #expect(save.displayName == "Save File")
        let expected: Shortcut = "cmd+shift+s"
        #expect(save.effectiveShortcuts.first == expected)
        #expect(save.isCustomized == true)
        #expect(save.kind == .discrete)
    }

    @Test("filter narrows rows; matches on displayName and ascii")
    func filterMatchesNameAndAscii() {
        let ctx = ShortcutContext<TableAct>("editor")
        let registry = ShortcutRegistry(contexts: [ctx], store: isolatedStore())
        let filteredByName = registry.keyBindings.filter(query: "save")
        #expect(filteredByName.groups[0].entries.map(\.actionID) == ["save"])

        let filteredByAscii = registry.keyBindings.filter(query: "cmd+z")
        #expect(filteredByAscii.groups[0].entries.map(\.actionID) == ["undo"])
    }

    @Test("rows expose all default bindings via effectiveShortcuts")
    func rowExposesAllBindings() {
        enum MultiAct: String, ShortcutAction, CaseIterable {
            case save
            var definition: ShortcutActionDefinition {
                .init("Save", defaults: [Shortcut("cmd+s"), Shortcut("ctrl+s")])
            }
        }
        let ctx = ShortcutContext<MultiAct>("editor")
        let registry = ShortcutRegistry(contexts: [ctx], store: isolatedStore())
        let row = registry.keyBindings.groups[0].entries.first!
        #expect(row.effectiveShortcuts.count == 2)
        #expect(row.effectiveShortcuts == [Shortcut("cmd+s"), Shortcut("ctrl+s")])
        #expect(row.effectiveShortcuts.first == Shortcut("cmd+s"))
    }

    @Test("legend(for:) returns only active contexts and only bound rows")
    func legendActiveOnly() {
        let editor = ShortcutContext<TableAct>("editor")
        let viewer = ShortcutContext<TableAct>("viewer")
        let registry = ShortcutRegistry(contexts: [editor, viewer], store: isolatedStore())
        let legend = registry.bindings(for: ["editor"]).boundOnly()
        #expect(legend.groups.map(\.contextID) == ["editor"])
        #expect(legend.groups[0].entries.count == 3)
    }
}
