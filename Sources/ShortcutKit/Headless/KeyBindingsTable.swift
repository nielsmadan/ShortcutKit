import ShortcutField

/// Sectioned view over the registry's bindings — one section per context, one
/// row per (context, action). Pure value type; Phase 2 renders it.
///
/// At this stage (Task 5) the registry publishes an empty table; Task 15
/// fills it in.
public struct KeyBindingsTable: Sendable, Hashable {
    public struct Row: Sendable, Hashable {
        public let contextID: String
        public let actionID: String
        public let displayName: String
        public let kind: Shortcut.Kind
        public let effectiveShortcut: Shortcut?
        public let isCustomized: Bool
        public let conflicts: [Conflict]
    }

    public struct Section: Sendable, Hashable {
        public let contextID: String
        public let rows: [Row]
    }

    public let sections: [Section]
    public init(sections: [Section] = []) {
        self.sections = sections
    }
}
