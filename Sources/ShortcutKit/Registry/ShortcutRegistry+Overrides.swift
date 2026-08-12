import ShortcutField

public extension ShortcutRegistry {
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

    package func setShortcuts(_ shortcuts: [Shortcut], contextID: String, actionID: String) {
        overrides[contextID, default: [:]][actionID] = shortcuts
        notifyChange(contextID: contextID, actionID: actionID)
        scheduleSave()
    }

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

    package func reset(contextID: String, actionID: String) {
        guard overrides[contextID]?[actionID] != nil else { return }
        overrides[contextID]?.removeValue(forKey: actionID)
        if overrides[contextID]?.isEmpty == true {
            overrides.removeValue(forKey: contextID)
        }
        notifyChange(contextID: contextID, actionID: actionID)
        scheduleSave()
    }

    package func resetAll(contextID: String) {
        guard let perAction = overrides[contextID] else { return }
        overrides.removeValue(forKey: contextID)
        for actionID in perAction.keys {
            notifyChange(contextID: contextID, actionID: actionID)
        }
        scheduleSave()
    }

    package func contextIDsWithConflicts() -> Set<String> {
        var ids: Set<String> = []
        for conflict in conflicts {
            for occurrence in conflict.occurrences {
                ids.insert(occurrence.contextID)
            }
        }
        return ids
    }

    package func scope(forContextID contextID: String) -> ContextScope {
        contexts.first(where: { $0.id == contextID })?.scope ?? .local
    }

    package var allContexts: [AnyShortcutContext] { contexts }

    private func notifyChange(contextID: String, actionID: String) {
        guard let context = contexts.first(where: { $0.id == contextID }) else { return }
        (context as? RegistryAttachable)?.__notifyOverrideChange(actionID: actionID)
        matchers[contextID]?.rebuild()
        for matcher in activeMatchers.values where matcher.contextID == contextID {
            matcher.rebuild()
        }
        reanalyzeConflicts()
        rebuildKeyBindings()
    }
}
