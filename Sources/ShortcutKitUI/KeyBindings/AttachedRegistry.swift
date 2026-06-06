import ShortcutKit

/// Resolves the `ShortcutRegistry` a context is attached to, for the inline UI
/// entry points (`ShortcutBindingEditor`, `KeyBindingsView`'s single-context
/// init) that take a context rather than a registry for ergonomics.
///
/// Passing a context that was never added to a `ShortcutRegistry(contexts:)` is
/// a programmer error: there's no registry to route edits through, so the view
/// would render nothing and silently drop every keystroke. We trap in debug so
/// the adopter catches the wiring mistake the first time they run it, and fall
/// back to an empty registry in release so a shipped app degrades to an inert
/// view rather than crashing on an end user.
@MainActor
func attachedRegistry<Action: ShortcutAction>(
    for context: ShortcutContext<Action>
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
