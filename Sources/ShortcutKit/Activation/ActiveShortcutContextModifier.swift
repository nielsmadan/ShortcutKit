import SwiftUI

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
    /// Activates `context` and binds its dispatch handler for the view's lifetime.
    ///
    /// Stacks additively when applied at multiple nesting levels; the
    /// innermost wins event priority.
    ///
    /// Global contexts bind their handler at construction and are activated
    /// system-wide through a `GlobalActivator`.
    func activeShortcutContext<A: ShortcutAction>(
        _ context: ShortcutContext<A>,
        dispatch handler: @escaping @MainActor (A, ShortcutDispatch) -> Void
    ) -> some View {
        modifier(ActiveShortcutContextModifier(context: context, handler: handler))
    }
}
