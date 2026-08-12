import ShortcutField

package extension ShortcutRegistry {
    func dispatchGlobalAction(_ ref: ActionRef) {
        guard let context = allContexts.first(where: { $0.id == ref.contextID }),
              let attachable = context as? RegistryAttachable
        else { return }
        attachable.__dispatchFromMatcher(actionID: ref.actionID)
    }

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
