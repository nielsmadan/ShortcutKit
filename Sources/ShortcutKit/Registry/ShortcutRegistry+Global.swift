import ShortcutField

public extension ShortcutRegistry {
    /// Fires an action's dispatch closure with `source: .shortcut`, emitting
    /// the same `actionFired` event a local matcher-driven fire would. The
    /// type-erased entry point used by `GlobalActivator` implementations
    /// (which work in the `String`-ID world). No-op for an unknown
    /// context/action.
    func fireGlobalAction(contextID: String, actionID: String) {
        guard let context = allContexts.first(where: { $0.id == contextID }),
              let attachable = context as? RegistryAttachable
        else { return }
        attachable.__dispatchFromMatcher(actionID: actionID)
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
