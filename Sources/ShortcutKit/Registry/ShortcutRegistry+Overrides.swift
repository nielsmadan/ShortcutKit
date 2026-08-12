import ShortcutField

public extension ShortcutRegistry {
    /// Reset every override across every context.
    func resetAll() {
        let snapshot = overrides
        overrides.removeAll()
        let refs = snapshot.flatMap { contextID, perAction in
            perAction.keys.map { ActionRef(contextID: contextID, actionID: $0) }
        }
        notifyChanges(refs)
        scheduleSave()
    }

    package func setShortcuts(_ shortcuts: [Shortcut], contextID: String, actionID: String) {
        overrides[contextID, default: [:]][actionID] = shortcuts
        notifyChanges([ActionRef(contextID: contextID, actionID: actionID)])
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
        notifyChanges([ActionRef(contextID: contextID, actionID: actionID)])
        scheduleSave()
    }

    package func reset(contextID: String, actionID: String) {
        guard overrides[contextID]?[actionID] != nil else { return }
        overrides[contextID]?.removeValue(forKey: actionID)
        if overrides[contextID]?.isEmpty == true {
            overrides.removeValue(forKey: contextID)
        }
        notifyChanges([ActionRef(contextID: contextID, actionID: actionID)])
        scheduleSave()
    }

    package func resetAll(contextID: String) {
        guard let perAction = overrides[contextID] else { return }
        overrides.removeValue(forKey: contextID)
        notifyChanges(perAction.keys.map { ActionRef(contextID: contextID, actionID: $0) })
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

    private func notifyChanges(_ refs: some Sequence<ActionRef>) {
        let refs = Array(refs)
        guard !refs.isEmpty else { return }
        let contextsByID = Dictionary(uniqueKeysWithValues: contexts.map { ($0.id, $0) })
        for ref in refs {
            (contextsByID[ref.contextID] as? RegistryAttachable)?
                .__notifyOverrideChange(actionID: ref.actionID)
        }
        let affectedContextIDs = Set(refs.map(\.contextID))
        for contextID in affectedContextIDs {
            matchers[contextID]?.rebuild()
        }
        for matcher in activeMatchers.values where affectedContextIDs.contains(matcher.contextID) {
            matcher.rebuild()
        }
        refreshDerivedState()
    }
}
