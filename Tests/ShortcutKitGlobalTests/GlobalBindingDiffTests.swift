import ShortcutField
@testable import ShortcutKit
@testable import ShortcutKitGlobal
import Testing

@Suite("GlobalBindingDiff") struct GlobalBindingDiffTests {
    private func id(_ action: String, _ index: Int = 0) -> BindingID {
        BindingID(contextID: "g", actionID: action, bindingIndex: index)
    }

    @Test("new bindings are added, removed bindings dropped, changed re-registered")
    func diffPartitions() {
        let old: [BindingID: Shortcut] = [
            id("keep"): Shortcut("ctrl+opt+cmd+k"),
            id("drop"): Shortcut("ctrl+opt+cmd+d"),
            id("change"): Shortcut("ctrl+opt+cmd+c"),
        ]
        let new: [BindingID: Shortcut] = [
            id("keep"): Shortcut("ctrl+opt+cmd+k"),
            id("change"): Shortcut("ctrl+opt+cmd+x"),
            id("add"): Shortcut("ctrl+opt+cmd+a"),
        ]
        let diff = GlobalBindingDiff.compute(old: old, new: new)

        #expect(Set(diff.toRemove) == [id("drop"), id("change")])
        #expect(Set(diff.toAdd.map(\.id)) == [id("add"), id("change")])
        #expect(diff.unchanged == [id("keep")])
    }

    @Test("identical sets produce an empty diff")
    func noChange() {
        let same: [BindingID: Shortcut] = [id("a"): Shortcut("ctrl+opt+cmd+a")]
        let diff = GlobalBindingDiff.compute(old: same, new: same)
        #expect(diff.toRemove.isEmpty)
        #expect(diff.toAdd.isEmpty)
        #expect(diff.unchanged == [id("a")])
    }
}
