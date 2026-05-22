import ShortcutField

public extension ShortcutRegistry {
    /// Set or clear an override for one action in one context. Passing `nil`
    /// clears the override (the action falls back to its declared defaults).
    /// Writes are debounced 250 ms to the underlying store.
    func setOverride(contextID: String, actionID: String, shortcut: Shortcut?) {
        if let shortcut {
            overrides[contextID, default: [:]][actionID] = [shortcut]
        } else {
            overrides[contextID]?.removeValue(forKey: actionID)
            if overrides[contextID]?.isEmpty == true {
                overrides.removeValue(forKey: contextID)
            }
        }
        notifyChange(contextID: contextID, actionID: actionID)
        scheduleSave()
    }

    /// Set the full list of override bindings for one action in one context.
    func setShortcuts<A: ShortcutAction>(
        _ shortcuts: [Shortcut], for action: A, in context: ShortcutContext<A>
    ) {
        overrides[context.id, default: [:]][action.rawValue] = shortcuts
        notifyChange(contextID: context.id, actionID: action.rawValue)
        scheduleSave()
    }

    /// Clear all overrides for a single context.
    func clearAllOverrides(contextID: String) {
        guard let perAction = overrides[contextID] else { return }
        overrides.removeValue(forKey: contextID)
        for actionID in perAction.keys {
            notifyChange(contextID: contextID, actionID: actionID)
        }
        scheduleSave()
    }

    /// Clear one override.
    func reset(contextID: String, actionID: String) {
        setOverride(contextID: contextID, actionID: actionID, shortcut: nil)
    }

    /// Clear all overrides.
    func resetAll() {
        let snapshot = overrides
        overrides.removeAll()
        for (contextID, perAction) in snapshot {
            for actionID in perAction.keys {
                notifyChange(contextID: contextID, actionID: actionID)
            }
        }
        scheduleSave()
    }

    private func notifyChange(contextID: String, actionID: String) {
        guard let context = contexts.first(where: { $0.id == contextID }) else { return }
        (context as? RegistryAttachable)?.__notifyOverrideChange(actionID: actionID)
        reanalyzeConflicts()
        rebuildKeyBindingsTable()
    }
}
