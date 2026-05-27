import Foundation
import ShortcutField

/// One declared action in an adopter's app. The raw `String` value is the
/// stable persistence ID — never change it; rename via `ShortcutMigration`.
public protocol ShortcutAction:
    CaseIterable, Sendable,
    RawRepresentable where RawValue == String
{
    var definition: ShortcutActionDefinition { get }
}

/// Per-action metadata: display name, optional description, kind, and
/// zero-or-more default shortcuts.
///
/// `displayName` and `description` use `LocalizedStringResource` so adopters
/// who localize get language-switch reactivity at render time. String literals
/// keep working — `LocalizedStringResource` is `ExpressibleByStringLiteral`.
public struct ShortcutActionDefinition: Sendable {
    public let displayName: LocalizedStringResource
    public let description: LocalizedStringResource?
    public let kind: Shortcut.Kind
    public let defaultShortcuts: [Shortcut]

    /// Primary init. `kind` is inferred from the first default; falls back to
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
