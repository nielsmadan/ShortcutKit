import ShortcutField

/// One declared action in an adopter's app. The raw `String` value is the
/// stable persistence ID — never change it; rename via `ShortcutMigration`.
public protocol ShortcutAction:
    CaseIterable, Hashable, Sendable,
    RawRepresentable where RawValue == String
{
    var definition: ShortcutActionDefinition { get }
}

/// Per-action metadata: display name, kind, and optional default shortcut.
public struct ShortcutActionDefinition: Sendable {
    public let displayName: String
    public let kind: Shortcut.Kind
    public let defaultShortcut: Shortcut?

    /// Infers `kind` from `defaultShortcut`; falls back to `.discrete` when absent.
    public init(_ displayName: String, _ defaultShortcut: Shortcut? = nil) {
        self.displayName = displayName
        kind = defaultShortcut?.kind ?? .discrete
        self.defaultShortcut = defaultShortcut
    }

    /// Explicit `kind` for actions with no default shortcut.
    public init(_ displayName: String, kind: Shortcut.Kind) {
        self.displayName = displayName
        self.kind = kind
        defaultShortcut = nil
    }
}
