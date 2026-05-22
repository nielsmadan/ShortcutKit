import ShortcutKit
import SwiftUI

@MainActor
public struct SearchField: View {
    @Binding var query: String

    public init(query: Binding<String>) { _query = query }

    public var body: some View {
        TextField("Search", text: $query)
            .textFieldStyle(.roundedBorder)
    }

    /// Headless filter: match on action label OR any binding's display string. Case-insensitive.
    public static func filter(_ rows: [KeyBindingsTable.Row], query: String) -> [KeyBindingsTable.Row] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return rows }
        return rows.filter { row in
            if row.displayName.lowercased().contains(q) { return true }
            return row.effectiveShortcuts.contains { $0.displayString.lowercased().contains(q) }
        }
    }
}
