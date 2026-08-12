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

    /// Creates a definition, inferring `kind` from the first default or using
    /// `.discrete` when `defaults` is empty.
    ///
    /// Traps at definition time if `defaults` mixes discrete and continuous
    /// shortcuts — every default must share the action's kind.
    public init(
        _ displayName: LocalizedStringResource,
        description: LocalizedStringResource? = nil,
        defaults: [Shortcut] = []
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
    }

    /// Explicit `kind` for actions with no default shortcut.
    public init(
        _ displayName: LocalizedStringResource,
        description: LocalizedStringResource? = nil,
        kind: Shortcut.Kind
    ) {
        self.displayName = displayName
        self.description = description
        self.kind = kind
        defaultShortcuts = []
    }

    /// Convenience for the common case of a single default shortcut.
    public init(
        _ displayName: LocalizedStringResource,
        _ defaultShortcut: Shortcut,
        description: LocalizedStringResource? = nil
    ) {
        self.init(displayName, description: description, defaults: [defaultShortcut])
    }
}
