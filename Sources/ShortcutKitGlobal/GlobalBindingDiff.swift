import ShortcutField

/// Pure diff between two snapshots of global bindings, keyed by `BindingID`.
/// A binding whose shortcut changed appears in *both* `toRemove` and `toAdd`
/// (unregister the stale Carbon hotkey, register the new one).
enum GlobalBindingDiff {
    struct Result: Equatable {
        var toRemove: [BindingID]
        var toAdd: [(id: BindingID, shortcut: Shortcut)]
        var unchanged: [BindingID]

        static func == (lhs: Result, rhs: Result) -> Bool {
            Set(lhs.toRemove) == Set(rhs.toRemove)
                && Set(lhs.unchanged) == Set(rhs.unchanged)
                && Set(lhs.toAdd.map(\.id)) == Set(rhs.toAdd.map(\.id))
        }
    }

    static func compute(
        old: [BindingID: Shortcut],
        new: [BindingID: Shortcut]
    ) -> Result {
        var toRemove: [BindingID] = []
        var toAdd: [(id: BindingID, shortcut: Shortcut)] = []
        var unchanged: [BindingID] = []

        for (id, oldShortcut) in old {
            if let newShortcut = new[id] {
                if newShortcut == oldShortcut {
                    unchanged.append(id)
                } else {
                    toRemove.append(id)
                    toAdd.append((id, newShortcut))
                }
            } else {
                toRemove.append(id)
            }
        }
        for (id, newShortcut) in new where old[id] == nil {
            toAdd.append((id, newShortcut))
        }
        return Result(toRemove: toRemove, toAdd: toAdd, unchanged: unchanged)
    }
}
