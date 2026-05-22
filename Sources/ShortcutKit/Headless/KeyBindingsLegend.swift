import ShortcutField

/// Compact view of currently-active bindings for a HUD or cheat-sheet. Pure
/// value type; Phase 2 renders it.
public struct KeyBindingsLegend: Sendable, Hashable {
    public struct Entry: Sendable, Hashable {
        public let displayName: String
        public let shortcut: Shortcut
        public init(displayName: String, shortcut: Shortcut) {
            self.displayName = displayName
            self.shortcut = shortcut
        }
    }

    public struct Group: Sendable, Hashable {
        public let contextID: String
        public let entries: [Entry]
        public init(contextID: String, entries: [Entry]) {
            self.contextID = contextID
            self.entries = entries
        }
    }

    public let groups: [Group]
    public init(groups: [Group] = []) {
        self.groups = groups
    }
}
