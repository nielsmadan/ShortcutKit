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
@Suite("KeyBindingsTable") struct KeyBindingsTableTests {
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
        let table = registry.keyBindingsTable
        #expect(table.sections.count == 1)
        #expect(table.sections[0].contextID == "editor")
        #expect(table.sections[0].rows.map(\.actionID).sorted() == ["save", "undo", "zoom"])
    }

    @Test("rows carry displayName, kind, effectiveShortcuts, isCustomized")
    func rowFields() {
        let ctx = ShortcutContext<TableAct>("editor")
        let registry = ShortcutRegistry(contexts: [ctx], store: isolatedStore())
        registry.setOverride(contextID: "editor", actionID: "save", shortcut: "cmd+shift+s")
        let table = registry.keyBindingsTable
        let save = table.sections[0].rows.first { $0.actionID == "save" }!
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
        let filteredByName = registry.keyBindingsTable.filter(query: "save")
        #expect(filteredByName.sections[0].rows.map(\.actionID) == ["save"])

        let filteredByAscii = registry.keyBindingsTable.filter(query: "cmd+z")
        #expect(filteredByAscii.sections[0].rows.map(\.actionID) == ["undo"])
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
        let row = registry.keyBindingsTable.sections[0].rows.first!
        #expect(row.effectiveShortcuts.count == 2)
        #expect(row.effectiveShortcuts == [Shortcut("cmd+s"), Shortcut("ctrl+s")])
        #expect(row.effectiveShortcuts.first == Shortcut("cmd+s"))
    }

    @Test("legend(for:) returns only active contexts and only bound rows")
    func legendActiveOnly() {
        let editor = ShortcutContext<TableAct>("editor")
        let viewer = ShortcutContext<TableAct>("viewer")
        let registry = ShortcutRegistry(contexts: [editor, viewer], store: isolatedStore())
        let legend = registry.legend(for: ["editor"])
        #expect(legend.groups.map(\.contextID) == ["editor"])
        #expect(legend.groups[0].entries.count == 3)
    }
}
