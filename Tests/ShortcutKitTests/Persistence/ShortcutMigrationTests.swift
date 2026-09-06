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
    func renameActionMovesKey() throws {
        var s = state(["editor": ["save": "cmd+s"]])
        try ShortcutMigrationApplier.apply(
            [.renameAction(context: "editor", from: "save", to: "saveFile")], to: &s
        )
        let expected: Shortcut = "cmd+s"
        #expect(expect(s, equals: ["editor": ["saveFile": expected]]))
    }

    @Test("renameAction is idempotent")
    func renameActionIdempotent() throws {
        var s = state(["editor": ["save": "cmd+s"]])
        let migration: ShortcutMigration = .renameAction(context: "editor", from: "save", to: "saveFile")
        try ShortcutMigrationApplier.apply([migration, migration], to: &s)
        let expected: Shortcut = "cmd+s"
        #expect(expect(s, equals: ["editor": ["saveFile": expected]]))
    }

    @Test("renameAction with absent source is a no-op")
    func renameActionMissingSource() throws {
        var s = state(["editor": ["undo": "cmd+z"]])
        try ShortcutMigrationApplier.apply(
            [.renameAction(context: "editor", from: "save", to: "saveFile")], to: &s
        )
        let expected: Shortcut = "cmd+z"
        #expect(expect(s, equals: ["editor": ["undo": expected]]))
    }

    @Test("renameAction collision: source wins")
    func renameActionCollisionSourceWins() throws {
        var s = state(["editor": ["save": "cmd+s", "saveFile": "cmd+shift+s"]])
        try ShortcutMigrationApplier.apply(
            [.renameAction(context: "editor", from: "save", to: "saveFile")], to: &s
        )
        let expected: Shortcut = "cmd+s"
        #expect(expect(s, equals: ["editor": ["saveFile": expected]]))
    }

    @Test("moveAction relocates between contexts")
    func moveActionBetweenContexts() throws {
        var s = state(["editor": ["save": "cmd+s"]])
        try ShortcutMigrationApplier.apply(
            [.moveAction(
                from: ActionRef(contextID: "editor", actionID: "save"),
                to: ActionRef(contextID: "files", actionID: "save")
            )],
            to: &s
        )
        let expected: Shortcut = "cmd+s"
        #expect(expect(s, equals: ["files": ["save": expected]]))
    }

    @Test("resetOverride clears one key")
    func resetOverrideClearsKey() throws {
        var s = state(["editor": ["save": "cmd+s", "undo": "cmd+z"]])
        try ShortcutMigrationApplier.apply(
            [.resetOverride(context: "editor", action: "save")], to: &s
        )
        let expected: Shortcut = "cmd+z"
        #expect(expect(s, equals: ["editor": ["undo": expected]]))
    }

    @Test("renameContext merges with source-wins on collision")
    func renameContextMerges() throws {
        var s = state([
            "old": ["save": "cmd+s"],
            "new": ["save": "cmd+shift+s", "undo": "cmd+z"],
        ])
        try ShortcutMigrationApplier.apply(
            [.renameContext(from: "old", to: "new")], to: &s
        )
        let save: Shortcut = "cmd+s"
        let undo: Shortcut = "cmd+z"
        #expect(expect(s, equals: ["new": ["save": save, "undo": undo]]))
    }

    @Test(".custom runs the closure")
    func customRuns() throws {
        var s = state([:])
        try ShortcutMigrationApplier.apply(
            [.custom { $0.overrides["editor"] = ["save": ["cmd+s"]] }], to: &s
        )
        let expected: Shortcut = "cmd+s"
        #expect(expect(s, equals: ["editor": ["save": expected]]))
    }

    @Test("a throwing migration propagates and leaves the whole input unchanged")
    func customErrorIsAtomic() {
        struct DemoError: Error {}
        var s = state(["editor": ["save": "cmd+s"]])
        let original = s

        #expect(throws: DemoError.self) {
            try ShortcutMigrationApplier.apply([
                .renameAction(context: "editor", from: "save", to: "save-file"),
                .custom {
                    $0.overrides["partial"] = ["change": ["cmd+p"]]
                    throw DemoError()
                },
            ], to: &s)
        }

        let expected: Shortcut = "cmd+s"
        #expect(expect(s, equals: ["editor": ["save": expected]]))
        #expect(s == original)
    }
}
