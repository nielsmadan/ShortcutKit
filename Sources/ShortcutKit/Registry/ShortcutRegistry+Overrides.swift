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
        resetAction(contextID: contextID, actionID: actionID)
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

    /// Type-erased override write — used by `KeyBindingsView` in `ShortcutKitUI`,
    /// which can only see the registry through its string-keyed surface.
    /// Mirrors the effects of the typed `setShortcuts(_:for:in:)`.
    func setShortcuts(_ shortcuts: [Shortcut], contextID: String, actionID: String) {
        overrides[contextID, default: [:]][actionID] = shortcuts
        notifyChange(contextID: contextID, actionID: actionID)
        scheduleSave()
    }

    /// Type-erased per-binding clear. If the cleared binding is the last one
    /// remaining for this action, the action's override entry is removed
    /// entirely (the action falls back to its declared defaults).
    func removeShortcut(at index: Int, contextID: String, actionID: String) {
        var current = overrides[contextID]?[actionID] ?? []
        guard index >= 0, index < current.count else { return }
        current.remove(at: index)
        if current.isEmpty {
            overrides[contextID]?.removeValue(forKey: actionID)
            if overrides[contextID]?.isEmpty == true {
                overrides.removeValue(forKey: contextID)
            }
        } else {
            overrides[contextID, default: [:]][actionID] = current
        }
        notifyChange(contextID: contextID, actionID: actionID)
        scheduleSave()
    }

    /// Type-erased single-action reset. The shared body that `reset(contextID:actionID:)`
    /// delegates to. Early-returns when no override exists so subscribers and
    /// the debounced save aren't triggered for a no-op.
    func resetAction(contextID: String, actionID: String) {
        guard overrides[contextID]?[actionID] != nil else { return }
        overrides[contextID]?.removeValue(forKey: actionID)
        if overrides[contextID]?.isEmpty == true {
            overrides.removeValue(forKey: contextID)
        }
        notifyChange(contextID: contextID, actionID: actionID)
        scheduleSave()
    }

    /// Returns the set of context IDs that currently have any conflict.
    func contextIDsWithConflicts() -> Set<String> {
        var ids: Set<String> = []
        for conflict in conflicts {
            for occurrence in conflict.occurrences {
                ids.insert(occurrence.contextID)
            }
        }
        return ids
    }

    /// Looks up the `ContextScope` for a context by id, or `.local` if unknown.
    func scope(forContextID contextID: String) -> ContextScope {
        contexts.first(where: { $0.id == contextID })?.scope ?? .local
    }

    /// Public, type-erased view of registered contexts. Needed because
    /// `KeyBindingsView` in `ShortcutKitUI` can't see the package-internal
    /// stored `contexts` array.
    var allContexts: [any AnyShortcutContext] { contexts }

    private func notifyChange(contextID: String, actionID: String) {
        guard let context = contexts.first(where: { $0.id == contextID }) else { return }
        (context as? RegistryAttachable)?.__notifyOverrideChange(actionID: actionID)
        // Rebuild the live matcher for this context so override-driven changes
        // (new bindings, edited sensitivity on continuous shortcuts, etc.)
        // take effect immediately instead of waiting for a registry rebuild.
        matchers[contextID]?.rebuild()
        reanalyzeConflicts()
        rebuildKeyBindingsTable()
    }
}
