import ShortcutField

package extension ShortcutRegistry {
    /// Dispatches an action's handler with `source: .shortcut`, emitting the
    /// same `actionFired` event a local matcher-driven fire would. The entry
    /// point `GlobalActivator` implementations call when the OS routes a global
    /// hotkey. No-op for an unknown context/action.
    func dispatchGlobalAction(_ ref: ActionRef) {
        guard let context = allContexts.first(where: { $0.id == ref.contextID }),
              let attachable = context as? RegistryAttachable
        else { return }
        attachable.__dispatchFromMatcher(actionID: ref.actionID)
    }

    /// Effective bindings (defaults + overrides) of every `.global`-scoped
    /// context, in group/entry order. One result per binding; `bindingIndex`
    /// is the slot within the action's binding array.
    func globalBindings() -> [GlobalBinding] {
        var result: [GlobalBinding] = []
        let globalIDs = Set(allContexts.filter { $0.scope == .global }.map(\.id))
        for group in keyBindings.groups where globalIDs.contains(group.contextID) {
            for entry in group.entries {
                for (index, shortcut) in entry.effectiveShortcuts.enumerated() {
                    result.append(GlobalBinding(
                        id: BindingID(
                            contextID: entry.contextID,
                            actionID: entry.actionID,
                            bindingIndex: index
                        ),
                        shortcut: shortcut
                    ))
                }
            }
        }
        return result
    }
}
