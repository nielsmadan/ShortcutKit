import Foundation
import ShortcutField
@testable import ShortcutKit
import Testing

@MainActor
@Suite("RawStateAccessors") struct RawStateAccessorsTests {
    private let s: Shortcut = "cmd+s"
    private let n: Shortcut = "cmd+n"

    @Test("subscript reads existing override")
    func subscriptRead() {
        let state = RawState(overrides: ["editor": ["save": [s]]])
        #expect(state[context: "editor", action: "save"] == [s])
        #expect(state[context: "editor", action: "nope"] == nil)
        #expect(state[context: "missing", action: "save"] == nil)
    }

    @Test("subscript write creates nested entry")
    func subscriptWriteCreates() {
        var state = RawState()
        state[context: "editor", action: "save"] = [s]
        #expect(state.overrides == ["editor": ["save": [s]]])
    }

    @Test("subscript write nil removes action and prunes empty context")
    func subscriptWriteNilPrunes() {
        var state = RawState(overrides: ["editor": ["save": [s]]])
        state[context: "editor", action: "save"] = nil
        #expect(state.overrides.isEmpty)
    }

    @Test("subscript write empty array also prunes")
    func subscriptWriteEmptyPrunes() {
        var state = RawState(overrides: ["editor": ["save": [s]]])
        state[context: "editor", action: "save"] = []
        #expect(state.overrides.isEmpty)
    }

    @Test("subscript leaves sibling actions intact when one is cleared")
    func subscriptPrunesOnlyTarget() {
        var state = RawState(overrides: ["editor": ["save": [s], "new": [n]]])
        state[context: "editor", action: "save"] = nil
        #expect(state.overrides == ["editor": ["new": [n]]])
    }

    @Test("removeContext drops the whole entry")
    func removeContext() {
        var state = RawState(overrides: ["editor": ["save": [s]], "viewer": ["zoom": [n]]])
        state.removeContext("editor")
        #expect(state.overrides == ["viewer": ["zoom": [n]]])
    }

    @Test("contextIDs and actionIDs enumerate")
    func enumerators() {
        let state = RawState(overrides: ["editor": ["save": [s], "new": [n]], "viewer": ["zoom": [n]]])
        #expect(Set(state.contextIDs) == ["editor", "viewer"])
        #expect(Set(state.actionIDs(in: "editor")) == ["save", "new"])
        #expect(state.actionIDs(in: "missing") == [])
    }
}
