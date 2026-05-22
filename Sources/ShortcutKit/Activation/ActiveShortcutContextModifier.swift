import SwiftUI

/// SwiftUI modifier backing `.activeShortcutContext(_:)`. Activates the
/// context on appear; deactivates on disappear. Additive when chained — the
/// innermost (last-applied) modifier ends up at the top of the router's stack.
struct ActiveShortcutContextModifier: ViewModifier {
    let context: any AnyShortcutContext

    func body(content: Content) -> some View {
        content
            .onAppear { (context as? any ContextActivation)?.__activate() }
            .onDisappear { (context as? any ContextActivation)?.__deactivate() }
    }
}

public extension View {
    /// Activate `context` for the lifetime of this view. Stacks additively
    /// when applied at multiple nesting levels; the innermost wins event
    /// priority.
    func activeShortcutContext(_ context: some AnyShortcutContext) -> some View {
        modifier(ActiveShortcutContextModifier(context: context))
    }
}
