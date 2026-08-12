import SwiftUI

struct ActiveShortcutContextModifier<Action: ShortcutAction>: ViewModifier {
    let context: ShortcutContext<Action>
    let handler: @MainActor (Action, ShortcutDispatch) -> Void
    @State private var activationID = UUID()

    func body(content: Content) -> some View {
        content
            .onAppear {
                context.__setActiveHandler(handler, for: activationID)
                (context as any ContextActivation).__activate(activationID: activationID)
            }
            .onDisappear {
                (context as any ContextActivation).__deactivate(activationID: activationID)
                context.__clearActiveHandler(for: activationID)
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
