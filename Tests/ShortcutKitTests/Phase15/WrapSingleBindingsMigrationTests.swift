import Foundation
import ShortcutField
@testable import ShortcutKit
import Testing

@MainActor
@Suite("WrapSingleBindingsMigration") struct WrapSingleBindingsMigrationTests {
    // Legacy JSON stores each action's shortcut as a scalar.
    private static let legacyScalarJSON = Data("""
    {"overrides":{"editor":{"save":{"kind":"discrete","discrete":{"steps":\
    [{"keyCode":1,"modifiers":1048576,"type":"key"}]}}}}}
    """.utf8)

    // Current JSON stores each action's shortcuts as an array.
    private static let newArrayJSON = Data("""
    {"overrides":{"editor":{"save":[\
    {"kind":"discrete","discrete":{"steps":[{"keyCode":1,"modifiers":1048576,"type":"key"}]}},\
    {"kind":"discrete","discrete":{"steps":[{"keyCode":1,"modifiers":262144,"type":"key"}]}}\
    ]}}}
    """.utf8)

    @Test("legacy scalar JSON decodes as single-element arrays")
    func wrapsScalarsIntoSingleElementArrays() throws {
        let state = try JSONCoding.decode(Self.legacyScalarJSON)
        #expect(state.overrides["editor"]?["save"]?.count == 1)
        let expected: Shortcut = "cmd+s"
        #expect(state.overrides["editor"]?["save"]?.first == expected)
    }

    @Test("new array shape JSON decodes unchanged")
    func newArrayShapePassesThrough() throws {
        let state = try JSONCoding.decode(Self.newArrayJSON)
        #expect(state.overrides["editor"]?["save"]?.count == 2)
        let expectedA: Shortcut = "cmd+s"
        let expectedB: Shortcut = "ctrl+s"
        #expect(state.overrides["editor"]?["save"]?[0] == expectedA)
        #expect(state.overrides["editor"]?["save"]?[1] == expectedB)
    }

    @Test("legacy scalar TOML decodes as single-element array")
    func tomlScalarWraps() throws {
        let toml = """
        [editor]
        save = "cmd+s"
        """
        let state = try TOMLCoding.decode(toml)
        #expect(state.overrides["editor"]?["save"]?.count == 1)
        let expected: Shortcut = "cmd+s"
        #expect(state.overrides["editor"]?["save"]?.first == expected)
    }

    @Test("new-shape TOML array decodes unchanged")
    func tomlArrayPassesThrough() throws {
        let toml = """
        [editor]
        save = ["cmd+s", "ctrl+s"]
        """
        let state = try TOMLCoding.decode(toml)
        #expect(state.overrides["editor"]?["save"]?.count == 2)
        let expectedA: Shortcut = "cmd+s"
        let expectedB: Shortcut = "ctrl+s"
        #expect(state.overrides["editor"]?["save"]?[0] == expectedA)
        #expect(state.overrides["editor"]?["save"]?[1] == expectedB)
    }

    @Test("migration .custom is a no-op on already-new shape")
    func migrationIsIdempotent() {
        let savedShortcut: Shortcut = "cmd+s"
        let initial = RawState(overrides: ["editor": ["save": [savedShortcut]]])
        var once = initial
        ShortcutMigrationApplier.apply([WrapSingleBindingsMigration.entry], to: &once)
        var twice = once
        ShortcutMigrationApplier.apply([WrapSingleBindingsMigration.entry], to: &twice)
        #expect(once == initial)
        #expect(once == twice)
    }
}
