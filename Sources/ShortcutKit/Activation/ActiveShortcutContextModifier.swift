import SwiftUI

/// SwiftUI modifier backing `.activeShortcutContext(_:dispatch:)`. Sets the
/// view-bound handler on appear, pushes the context onto the registry's
/// matcher stack; clears the handler on disappear and pops the context.
/// Additive when chained — the innermost (last-applied) modifier ends up at
/// the top of the router's stack.
struct ActiveShortcutContextModifier<Action: ShortcutAction>: ViewModifier {
    let context: ShortcutContext<Action>
    let handler: @MainActor (Action, ShortcutDispatch) -> Void

    func body(content: Content) -> some View {
        content
            .onAppear {
                context.__setActiveHandler(handler)
                (context as any ContextActivation).__activate()
            }
            .onDisappear {
                (context as any ContextActivation).__deactivate()
                context.__clearActiveHandler()
            }
    }
}

public extension View {
    /// Activate `context` for the lifetime of this view and bind its
    /// dispatch handler. The handler closes over view-local state (e.g.
    /// `@State`-backed bindings); when the view goes away, the handler is
    /// cleared and the context is deactivated.
    ///
    /// Stacks additively when applied at multiple nesting levels; the
    /// innermost wins event priority.
    ///
    /// `.global` contexts don't use this modifier — their handler is bound
    /// at construction (`ShortcutContext(global:dispatch:)`) and they're
    /// activated system-wide via `ShortcutKitGlobal`.
    func activeShortcutContext<A: ShortcutAction>(
        _ context: ShortcutContext<A>,
        dispatch handler: @escaping @MainActor (A, ShortcutDispatch) -> Void
    ) -> some View {
        modifier(ActiveShortcutContextModifier(context: context, handler: handler))
    }
}
