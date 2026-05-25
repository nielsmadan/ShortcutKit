import ShortcutField

/// One declared action in an adopter's app. The raw `String` value is the
/// stable persistence ID — never change it; rename via `ShortcutMigration`.
public protocol ShortcutAction:
    CaseIterable, Sendable,
    RawRepresentable where RawValue == String
{
    var definition: ShortcutActionDefinition { get }
}

/// Per-action metadata: display name, kind, and zero-or-more default shortcuts.
public struct ShortcutActionDefinition: Sendable {
    public let displayName: String
    public let kind: Shortcut.Kind
    public let defaultShortcuts: [Shortcut]

    /// Primary init. `kind` is inferred from the first default; defaults to `.discrete`.
    public init(_ displayName: String, defaults: [Shortcut] = []) {
        self.displayName = displayName
        kind = defaults.first?.kind ?? .discrete
        defaultShortcuts = defaults
    }

    /// Explicit `kind` for actions with no default shortcut.
    public init(_ displayName: String, kind: Shortcut.Kind) {
        self.displayName = displayName
        self.kind = kind
        defaultShortcuts = []
    }

    /// Convenience matching Phase 1 single-binding ergonomics.
    public init(_ displayName: String, _ defaultShortcut: Shortcut) {
        self.init(displayName, defaults: [defaultShortcut])
    }
}
