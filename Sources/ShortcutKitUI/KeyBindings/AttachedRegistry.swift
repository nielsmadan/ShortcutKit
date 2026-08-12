import ShortcutKit

@MainActor
func attachedRegistry(
    for context: ShortcutContext<some ShortcutAction>
) -> ShortcutRegistry {
    if let registry = context.attachedRegistry {
        return registry
    }
    assertionFailure(
        "ShortcutContext '\(context.id)' is not attached to a ShortcutRegistry. "
            + "Build it via ShortcutRegistry(contexts:) before passing it to an inline view "
            + "(ShortcutBindingEditor / KeyBindingsView(context:))."
    )
    return ShortcutRegistry(contexts: [])
}
