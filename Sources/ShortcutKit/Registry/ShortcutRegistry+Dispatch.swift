import os.log

public extension ShortcutRegistry {
    /// Dispatches an action by persistence ID and emits a programmatic
    /// `actionFired` event.
    ///
    /// Unknown context or action IDs log a warning and do nothing.
    func dispatch(_ ref: ActionRef) {
        guard let context = dispatchable(ref.contextID, verb: "dispatch") else { return }
        if !context.__dispatchProgrammatic(actionID: ref.actionID) {
            Self.logger.warning(
                "dispatch ignored: no action '\(ref.actionID, privacy: .public)' in context '\(ref.contextID, privacy: .public)'"
            )
        }
    }

    /// Convenience for `dispatch(ActionRef(contextID:actionID:))`.
    func dispatch(contextID: String, actionID: String) {
        dispatch(ActionRef(contextID: contextID, actionID: actionID))
    }

    /// Emits a programmatic `actionFired` event without invoking the handler.
    /// Unknown IDs log a warning and do nothing.
    func notify(_ ref: ActionRef) {
        guard let context = dispatchable(ref.contextID, verb: "notify") else { return }
        if !context.__notifyProgrammatic(actionID: ref.actionID) {
            Self.logger.warning(
                "notify ignored: no action '\(ref.actionID, privacy: .public)' in context '\(ref.contextID, privacy: .public)'"
            )
        }
    }

    /// Convenience for `notify(ActionRef(contextID:actionID:))`.
    func notify(contextID: String, actionID: String) {
        notify(ActionRef(contextID: contextID, actionID: actionID))
    }

    private func dispatchable(_ contextID: String, verb: String) -> (any RegistryAttachable)? {
        guard let context = allContexts.first(where: { $0.id == contextID }) else {
            Self.logger.warning("\(verb, privacy: .public) ignored: no context '\(contextID, privacy: .public)'")
            return nil
        }
        return context as? RegistryAttachable
    }
}
