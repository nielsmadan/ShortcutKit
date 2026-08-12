import Foundation
import ShortcutField

/// A presentation-independent snapshot of effective bindings grouped by context.
///
/// `Equatable` but not `Hashable`: the entries carry `LocalizedStringResource`
/// (`displayName`/`description`), which is `Equatable` but not `Hashable`. Use
/// `Entry.id` / `Group.id` as the stable hashable key when one is needed.
public struct KeyBindings: Sendable, Equatable {
    /// The effective binding state for an action.
    public struct Entry: Sendable, Equatable, Identifiable {
        public let contextID: String
        public let actionID: String
        public let displayName: LocalizedStringResource
        public let description: LocalizedStringResource?
        public let kind: Shortcut.Kind
        public let effectiveShortcuts: [Shortcut]
        public let isCustomized: Bool
        /// Conflicts involving this entry.
        ///
        /// A conflict appears on every entry it involves; use the registry's
        /// `conflicts` collection for an app-wide count.
        public let conflicts: [Conflict]

        /// Stable identity unique across contexts.
        public var id: String { "\(contextID).\(actionID)" }

        public init(
            contextID: String, actionID: String,
            displayName: LocalizedStringResource,
            description: LocalizedStringResource? = nil,
            kind: Shortcut.Kind, effectiveShortcuts: [Shortcut],
            isCustomized: Bool, conflicts: [Conflict]
        ) {
            self.contextID = contextID
            self.actionID = actionID
            self.displayName = displayName
            self.description = description
            self.kind = kind
            self.effectiveShortcuts = effectiveShortcuts
            self.isCustomized = isCustomized
            self.conflicts = conflicts
        }
    }

    /// The entries belonging to one context.
    public struct Group: Sendable, Equatable, Identifiable {
        public let contextID: String
        public let displayName: LocalizedStringResource
        public let entries: [Entry]
        public var id: String { contextID }
        public init(contextID: String, displayName: LocalizedStringResource, entries: [Entry]) {
            self.contextID = contextID
            self.displayName = displayName
            self.entries = entries
        }
    }

    public let groups: [Group]
    public init(groups: [Group] = []) { self.groups = groups }

    /// Fuzzy-filters display names and ASCII binding strings case-insensitively.
    ///
    /// Results are sorted by descending score and empty groups are omitted.
    public func filter(query: String) -> KeyBindings {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return self }
        var filtered: [Group] = []
        for group in groups {
            let scored: [(Entry, Int)] = group.entries.compactMap { entry in
                let nameScore = FuzzyFilter.match(
                    query: trimmed, in: String(localized: entry.displayName)
                )?.score
                let asciiScore = entry.effectiveShortcuts
                    .compactMap { FuzzyFilter.match(query: trimmed, in: $0.ascii)?.score }
                    .max()
                guard let best = [nameScore, asciiScore].compactMap({ $0 }).max()
                else { return nil }
                return (entry, best)
            }
            .sorted { $0.1 > $1.1 }
            if !scored.isEmpty {
                filtered.append(Group(
                    contextID: group.contextID,
                    displayName: group.displayName,
                    entries: scored.map(\.0)
                ))
            }
        }
        return KeyBindings(groups: filtered)
    }

    /// Returns only entries with effective shortcuts, omitting empty groups.
    public func boundOnly() -> KeyBindings {
        var result: [Group] = []
        for group in groups {
            let bound = group.entries.filter { !$0.effectiveShortcuts.isEmpty }
            if !bound.isEmpty {
                result.append(Group(
                    contextID: group.contextID,
                    displayName: group.displayName,
                    entries: bound
                ))
            }
        }
        return KeyBindings(groups: result)
    }
}
