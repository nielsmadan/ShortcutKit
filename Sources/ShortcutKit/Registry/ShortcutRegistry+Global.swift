import ShortcutField

public extension ShortcutRegistry {
    /// Fires an action's dispatch closure with `viaShortcut: true`, emitting
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
    /// context, in section/row order. One entry per binding; `bindingIndex`
    /// is the slot within the action's binding array.
    func globalBindings() -> [(id: BindingID, shortcut: Shortcut)] {
        var result: [(id: BindingID, shortcut: Shortcut)] = []
        let globalIDs = Set(allContexts.filter { $0.scope == .global }.map(\.id))
        for section in keyBindingsTable.sections where globalIDs.contains(section.contextID) {
            for row in section.rows {
                for (index, shortcut) in row.effectiveShortcuts.enumerated() {
                    result.append((
                        id: BindingID(
                            contextID: row.contextID,
                            actionID: row.actionID,
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
