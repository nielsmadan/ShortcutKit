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
    /// - Parameter allowsKeyRepeat: When `false`, holding the key fires the
    ///   action once instead of repeating. Set it for actions where each
    ///   invocation costs something — deletions, toggles, sends. Leave it `true`
    ///   for actions built to repeat, like nudging or incrementing. Only affects
    ///   discrete actions; continuous shortcuts have no key-repeat.
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
