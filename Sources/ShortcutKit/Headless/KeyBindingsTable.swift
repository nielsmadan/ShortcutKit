import Foundation
import ShortcutField

public struct KeyBindingsTable: Sendable, Hashable {
    public struct Row: Sendable, Hashable {
        public let contextID: String
        public let actionID: String
        public let displayName: String
        public let kind: Shortcut.Kind
        public let effectiveShortcut: Shortcut?
        public let isCustomized: Bool
        public let conflicts: [Conflict]

        public init(
            contextID: String, actionID: String, displayName: String,
            kind: Shortcut.Kind, effectiveShortcut: Shortcut?,
            isCustomized: Bool, conflicts: [Conflict]
        ) {
            self.contextID = contextID
            self.actionID = actionID
            self.displayName = displayName
            self.kind = kind
            self.effectiveShortcut = effectiveShortcut
            self.isCustomized = isCustomized
            self.conflicts = conflicts
        }
    }

    public struct Section: Sendable, Hashable {
        public let contextID: String
        public let rows: [Row]
        public init(contextID: String, rows: [Row]) {
            self.contextID = contextID
            self.rows = rows
        }
    }

    public let sections: [Section]
    public init(sections: [Section] = []) { self.sections = sections }

    /// Fuzzy filter — case-insensitive match on `displayName` and the binding's
    /// `ascii` string. Rows are sorted within each section by descending score;
    /// empty sections are dropped.
    public func filter(query: String) -> KeyBindingsTable {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return self }
        var filtered: [Section] = []
        for section in sections {
            let scored: [(Row, Int)] = section.rows.compactMap { row in
                let nameScore = FuzzyFilter.match(query: trimmed, in: row.displayName)?.score
                let asciiScore = row.effectiveShortcut
                    .flatMap { FuzzyFilter.match(query: trimmed, in: $0.ascii)?.score }
                guard let best = [nameScore, asciiScore].compactMap({ $0 }).max()
                else { return nil }
                return (row, best)
            }
            .sorted { $0.1 > $1.1 }
            if !scored.isEmpty {
                filtered.append(Section(contextID: section.contextID, rows: scored.map(\.0)))
            }
        }
        return KeyBindingsTable(sections: filtered)
    }
}
