import ShortcutField
import ShortcutKit
import SwiftUI

/// An editor for one action in a custom preferences or onboarding layout.
/// It displays bindings, conflicts, reset control, and an optional description.
///
/// ```swift
/// VStack(spacing: 16) {
///     ShortcutBindingEditor(.save, in: editorContext, showsDescription: true)
///     ShortcutBindingEditor(.togglePalette, in: globalContext, showsDescription: true)
/// }
/// ```
///
/// The context must already be attached to a ``ShortcutRegistry``.
@MainActor
public struct ShortcutBindingEditor<Action: ShortcutAction>: View {
    @ObservedObject private var registry: ShortcutRegistry
    private let action: Action
    private let context: ShortcutContext<Action>
    private let style: KeyBindingsStyle
    private let showsDescription: Bool

    public init(
        _ action: Action,
        in context: ShortcutContext<Action>,
        style: KeyBindingsStyle = .regular,
        showsDescription: Bool = false
    ) {
        self.action = action
        self.context = context
        self.style = style
        self.showsDescription = showsDescription
        registry = attachedRegistry(for: context)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let entry {
                ShortcutRowView(
                    row: entry,
                    policy: ScopePolicy(context.scope),
                    style: style,
                    onSet: { registry.setShortcuts($0, contextID: context.id, actionID: action.rawValue) },
                    onClear: { registry.removeShortcut(at: $0, contextID: context.id, actionID: action.rawValue) },
                    onReset: { registry.reset(contextID: context.id, actionID: action.rawValue) }
                )
                if showsDescription, let description = action.definition.description {
                    Text(description)
                        .font(.system(size: style == .dense ? 9 : 11))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    var entry: KeyBindings.Entry? {
        registry.keyBindings.groups
            .first { $0.contextID == context.id }?
            .entries.first { $0.actionID == action.rawValue }
    }
}
