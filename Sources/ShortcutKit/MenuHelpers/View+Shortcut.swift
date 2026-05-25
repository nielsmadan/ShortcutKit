import ShortcutField
import SwiftUI

public extension View {
    /// Apply `.keyboardShortcut(...)` from `action`'s effective binding if it
    /// is a single-step keyboard discrete shortcut. No-op otherwise.
    /// Updates when the binding changes.
    ///
    /// Does **not** wire dispatch — write your own SwiftUI handler (e.g. a
    /// `Button(action:)`); this only supplies the keyboard shortcut hint.
    func shortcut<A>(
        _ action: A,
        in context: ShortcutContext<A>
    ) -> some View {
        modifier(ShortcutKitKeyboardShortcutModifier(action: action, context: context))
    }
}

/// Internal: re-applies `.keyboardShortcut(...)` as the bound shortcut changes.
struct ShortcutKitKeyboardShortcutModifier<A: ShortcutAction>: ViewModifier {
    let action: A
    let context: ShortcutContext<A>
    @State private var current: Shortcut?

    func body(content: Content) -> some View {
        Group {
            if let (key, mods) = ShortcutKitHelpers.resolveKeyboardEquivalent(
                for: action, in: context, given: current
            ) {
                content.keyboardShortcut(key, modifiers: mods)
            } else {
                content
            }
        }
        .onAppear { current = context.shortcut(for: action) }
        .onReceive(context.shortcutChanges(for: action)) { current = $0 }
    }
}

/// Helpers for resolving SwiftUI keyboard equivalents from ShortcutKit bindings.
enum ShortcutKitHelpers {
    @MainActor
    static func resolveKeyboardEquivalent<A: ShortcutAction>(
        for action: A,
        in context: ShortcutContext<A>,
        given current: Shortcut? = nil
    ) -> (KeyEquivalent, EventModifiers)? {
        let shortcut = current ?? context.shortcut(for: action)
        guard case let .discrete(discrete) = shortcut,
              discrete.steps.count == 1,
              case let .key(keyCode) = discrete.steps[0].kind,
              let character = MenuKeyMapping.character(for: keyCode),
              let scalar = character.unicodeScalars.first
        else { return nil }
        return (KeyEquivalent(Character(scalar)), swiftUIModifiers(discrete.steps[0].modifiers))
    }

    private static func swiftUIModifiers(_ ns: NSEvent.ModifierFlags) -> EventModifiers {
        var out: EventModifiers = []
        if ns.contains(.command) { out.insert(.command) }
        if ns.contains(.shift) { out.insert(.shift) }
        if ns.contains(.option) { out.insert(.option) }
        if ns.contains(.control) { out.insert(.control) }
        return out
    }
}
