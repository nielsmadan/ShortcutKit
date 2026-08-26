import Foundation
import ShortcutField

/// A shortcut action whose raw value is its stable persistence ID.
///
/// Rename raw values only through a `ShortcutMigration`.
public protocol ShortcutAction:
    CaseIterable, Sendable,
    RawRepresentable where RawValue == String
{
    var definition: ShortcutActionDefinition { get }
}

/// Display metadata, kind, and default shortcuts for an action.
public struct ShortcutActionDefinition: Sendable {
    public let displayName: LocalizedStringResource
    public let description: LocalizedStringResource?
    public let kind: Shortcut.Kind
    public let defaultShortcuts: [Shortcut]
    public let allowsKeyRepeat: Bool

    /// Creates a definition, inferring `kind` from the first default or using
    /// `.discrete` when `defaults` is empty.
    ///
    /// Traps at definition time if `defaults` mixes discrete and continuous
    /// shortcuts — every default must share the action's kind.
    ///
    /// Setting `allowsKeyRepeat` to `false` makes holding the key fire the action
    /// once instead of repeating — for actions where each invocation costs
    /// something, like deletions, toggles, and sends. Leave it `true` for actions
    /// built to repeat, like nudging. Discrete actions only; continuous shortcuts
    /// have no key-repeat.
    public init(
        _ displayName: LocalizedStringResource,
        description: LocalizedStringResource? = nil,
        defaults: [Shortcut] = [],
        allowsKeyRepeat: Bool = true
    ) {
        let inferredKind = defaults.first?.kind ?? .discrete
        precondition(
            defaults.allSatisfy { $0.kind == inferredKind },
            "ShortcutActionDefinition has mixed-kind defaults; every default must be \(inferredKind)."
        )
        self.displayName = displayName
        self.description = description
        kind = inferredKind
        defaultShortcuts = defaults
        self.allowsKeyRepeat = allowsKeyRepeat
    }

    /// Explicit `kind` for actions with no default shortcut.
    public init(
        _ displayName: LocalizedStringResource,
        description: LocalizedStringResource? = nil,
        kind: Shortcut.Kind,
        allowsKeyRepeat: Bool = true
    ) {
        self.displayName = displayName
        self.description = description
        self.kind = kind
        defaultShortcuts = []
        self.allowsKeyRepeat = allowsKeyRepeat
    }

    /// Convenience for the common case of a single default shortcut.
    public init(
        _ displayName: LocalizedStringResource,
        _ defaultShortcut: Shortcut,
        description: LocalizedStringResource? = nil,
        allowsKeyRepeat: Bool = true
    ) {
        self.init(
            displayName,
            description: description,
            defaults: [defaultShortcut],
            allowsKeyRepeat: allowsKeyRepeat
        )
    }
}
