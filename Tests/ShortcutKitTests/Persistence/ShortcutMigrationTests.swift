import Foundation
@testable import ShortcutKit
import Testing

@MainActor
@Suite("ShortcutMigration") struct ShortcutMigrationTests {
    private func state(_ overrides: [String: [String: Shortcut]]) -> RawState {
        RawState(overrides: overrides.mapValues { $0.mapValues { [$0] } })
    }

    private func expect(
        _ state: RawState, equals scalarOverrides: [String: [String: Shortcut]]
    ) -> Bool {
        state.overrides == scalarOverrides.mapValues { $0.mapValues { [$0] } }
    }

    @Test("renameAction moves a key")
    func renameActionMovesKey() {
        var s = state(["editor": ["save": "cmd+s"]])
        ShortcutMigrationApplier.apply(
            [.renameAction(context: "editor", from: "save", to: "saveFile")], to: &s
        )
        let expected: Shortcut = "cmd+s"
        #expect(expect(s, equals: ["editor": ["saveFile": expected]]))
    }

    @Test("renameAction is idempotent")
    func renameActionIdempotent() {
        var s = state(["editor": ["save": "cmd+s"]])
        let migration: ShortcutMigration = .renameAction(context: "editor", from: "save", to: "saveFile")
        ShortcutMigrationApplier.apply([migration, migration], to: &s)
        let expected: Shortcut = "cmd+s"
        #expect(expect(s, equals: ["editor": ["saveFile": expected]]))
    }

    @Test("renameAction with absent source is a no-op")
    func renameActionMissingSource() {
        var s = state(["editor": ["undo": "cmd+z"]])
        ShortcutMigrationApplier.apply(
            [.renameAction(context: "editor", from: "save", to: "saveFile")], to: &s
        )
        let expected: Shortcut = "cmd+z"
        #expect(expect(s, equals: ["editor": ["undo": expected]]))
    }

    @Test("renameAction collision: source wins")
    func renameActionCollisionSourceWins() {
        var s = state(["editor": ["save": "cmd+s", "saveFile": "cmd+shift+s"]])
        ShortcutMigrationApplier.apply(
            [.renameAction(context: "editor", from: "save", to: "saveFile")], to: &s
        )
        let expected: Shortcut = "cmd+s"
        #expect(expect(s, equals: ["editor": ["saveFile": expected]]))
    }

    @Test("moveAction relocates between contexts")
    func moveActionBetweenContexts() {
        var s = state(["editor": ["save": "cmd+s"]])
        ShortcutMigrationApplier.apply(
            [.moveAction(from: (context: "editor", action: "save"),
                         to: (context: "files", action: "save"))],
            to: &s
        )
        let expected: Shortcut = "cmd+s"
        #expect(expect(s, equals: ["files": ["save": expected]]))
    }

    @Test("resetOverride clears one key")
    func resetOverrideClearsKey() {
        var s = state(["editor": ["save": "cmd+s", "undo": "cmd+z"]])
        ShortcutMigrationApplier.apply(
            [.resetOverride(context: "editor", action: "save")], to: &s
        )
        let expected: Shortcut = "cmd+z"
        #expect(expect(s, equals: ["editor": ["undo": expected]]))
    }

    @Test("renameContext merges with source-wins on collision")
    func renameContextMerges() {
        var s = state([
            "old": ["save": "cmd+s"],
            "new": ["save": "cmd+shift+s", "undo": "cmd+z"],
        ])
        ShortcutMigrationApplier.apply(
            [.renameContext(from: "old", to: "new")], to: &s
        )
        let save: Shortcut = "cmd+s"
        let undo: Shortcut = "cmd+z"
        #expect(expect(s, equals: ["new": ["save": save, "undo": undo]]))
    }

    @Test(".custom runs the closure")
    func customRuns() {
        var s = state([:])
        ShortcutMigrationApplier.apply(
            [.custom { $0.overrides["editor"] = ["save": ["cmd+s"]] }], to: &s
        )
        let expected: Shortcut = "cmd+s"
        #expect(expect(s, equals: ["editor": ["save": expected]]))
    }

    @Test(".custom errors are caught — state stays as it was")
    func customErrorCaught() {
        struct DemoError: Error {}
        var s = state(["editor": ["save": "cmd+s"]])
        ShortcutMigrationApplier.apply(
            [.custom { _ in throw DemoError() }], to: &s
        )
        let expected: Shortcut = "cmd+s"
        #expect(expect(s, equals: ["editor": ["save": expected]]))
    }
}
