import os.log

public extension ShortcutRegistry {
    /// Run an action's handler by reference — the registry-level counterpart to
    /// `ShortcutContext.dispatch(_:)` for when you hold the IDs rather than the
    /// typed context (a command palette, a URL-scheme handler, replay of a
    /// persisted `ActionRef`). Routes to the context named by `ref.contextID`,
    /// invokes its bound handler, and emits `actionFired(source: .programmatic)`
    /// — so the hint HUD treats it like any other non-shortcut invocation.
    ///
    /// A no-op (with a logged warning) if the context or action id is unknown;
    /// ids can come from stale persisted data, so this never traps.
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

    /// Record that an action fired without running its handler — the
    /// registry-level counterpart to `ShortcutContext.notify(_:)`. Emits
    /// `actionFired(source: .programmatic)` for the referenced action. Same
    /// unknown-id behavior as `dispatch(_:)`.
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
