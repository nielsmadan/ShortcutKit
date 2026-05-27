import ShortcutKit
import SwiftUI

@MainActor
struct SearchField: View {
    @Binding var query: String

    init(query: Binding<String>) { _query = query }

    var body: some View {
        TextField("Search", text: $query)
            .textFieldStyle(.roundedBorder)
    }

    /// Headless filter: match on action label OR any binding's display string. Case-insensitive.
    static func filter(_ rows: [KeyBindingsTable.Row], query: String) -> [KeyBindingsTable.Row] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return rows }
        return rows.filter { row in
            if String(localized: row.displayName).lowercased().contains(q) { return true }
            return row.effectiveShortcuts.contains { $0.displayString.lowercased().contains(q) }
        }
    }
}
