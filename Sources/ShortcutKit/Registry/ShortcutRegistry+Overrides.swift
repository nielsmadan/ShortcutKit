import ShortcutField

public extension ShortcutRegistry {
    // MARK: - Override mutation (adopter-facing)

    //
    // Per-action / per-context typed mutations live on `ShortcutContext`
    // (`setShortcuts(_:for:)`, `reset(_:)`, `resetAll()`) — the typed handle the
    // adopter holds. The registry keeps only the whole-app `resetAll()` plus the
    // string-keyed surface `ShortcutKitUI` needs (below).

    /// Reset every override across every context.
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

    // MARK: - Override mutation (string-keyed, cross-module for ShortcutKitUI)

    /// String-keyed equivalent of `setShortcuts(_:for:in:)` — the surface
    /// `ShortcutKitUI` uses, since it sees actions through string IDs.
    package func setShortcuts(_ shortcuts: [Shortcut], contextID: String, actionID: String) {
        overrides[contextID, default: [:]][actionID] = shortcuts
        notifyChange(contextID: contextID, actionID: actionID)
        scheduleSave()
    }

    /// Remove one binding slot by index. If it was the last, the action's
    /// override entry is removed (falls back to declared defaults).
    package func removeShortcut(at index: Int, contextID: String, actionID: String) {
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

    /// String-keyed equivalent of `reset(_:in:)`. Early-returns on no-op so
    /// subscribers and the debounced save aren't triggered needlessly.
    package func reset(contextID: String, actionID: String) {
        guard overrides[contextID]?[actionID] != nil else { return }
        overrides[contextID]?.removeValue(forKey: actionID)
        if overrides[contextID]?.isEmpty == true {
            overrides.removeValue(forKey: contextID)
        }
        notifyChange(contextID: contextID, actionID: actionID)
        scheduleSave()
    }

    /// Reset every override in one context. Called by `ShortcutContext.resetAll()`.
    package func resetAll(contextID: String) {
        guard let perAction = overrides[contextID] else { return }
        overrides.removeValue(forKey: contextID)
        for actionID in perAction.keys {
            notifyChange(contextID: contextID, actionID: actionID)
        }
        scheduleSave()
    }

    /// Returns the set of context IDs that currently have any conflict.
    package func contextIDsWithConflicts() -> Set<String> {
        var ids: Set<String> = []
        for conflict in conflicts {
            for occurrence in conflict.occurrences {
                ids.insert(occurrence.contextID)
            }
        }
        return ids
    }

    /// Looks up the `ContextScope` for a context by id, or `.local` if unknown.
    package func scope(forContextID contextID: String) -> ContextScope {
        contexts.first(where: { $0.id == contextID })?.scope ?? .local
    }

    /// Type-erased view of registered contexts. Needed because `ShortcutKitUI`
    /// can't see the package-internal stored `contexts` array.
    package var allContexts: [any AnyShortcutContext] { contexts }

    private func notifyChange(contextID: String, actionID: String) {
        guard let context = contexts.first(where: { $0.id == contextID }) else { return }
        (context as? RegistryAttachable)?.__notifyOverrideChange(actionID: actionID)
        // Rebuild the live matcher for this context so override-driven changes
        // (new bindings, edited sensitivity on continuous shortcuts, etc.)
        // take effect immediately instead of waiting for a registry rebuild.
        matchers[contextID]?.rebuild()
        reanalyzeConflicts()
        rebuildKeyBindings()
    }
}
