import ShortcutField
import ShortcutKit
import SwiftUI

/// Edits one action's shortcut, bound to `(action, context)` and persisting
/// through the context's attached registry. Renders the action's display name,
/// an optional description, the recorder(s) for its current bindings (with
/// scope validation + conflict feedback), and a reset-to-default button.
///
/// Unlike the whole-table `KeyBindingsView`, this is a single row you can place
/// anywhere — an onboarding step asking for the few most important shortcuts, a
/// custom preferences layout, a contextual popover. Compose several for a
/// curated set:
///
/// ```swift
/// VStack(spacing: 16) {
///     ShortcutBindingEditor(.save,          in: editorContext, showsDescription: true)
///     ShortcutBindingEditor(.togglePalette, in: globalContext, showsDescription: true)
/// }
/// ```
///
/// The context must already be attached to a `ShortcutRegistry` (constructed and
/// passed via `ShortcutRegistry(contexts:)`) so edits route through it.
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
                    // Same size/weight as KeyBindingsView's row subtitle so the same
                    // description reads identically; unbounded here (no `lineLimit`)
                    // since a single onboarding row can afford the full sentence.
                    Text(description)
                        .font(.system(size: style == .dense ? 9 : 11))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    /// The current binding entry for this (context, action), from the registry's
    /// live snapshot. `nil` if the context isn't registered.
    var entry: KeyBindings.Entry? {
        registry.keyBindings.groups
            .first { $0.contextID == context.id }?
            .entries.first { $0.actionID == action.rawValue }
    }
}
