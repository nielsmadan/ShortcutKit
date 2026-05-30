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
    static func filter(_ entries: [KeyBindings.Entry], query: String) -> [KeyBindings.Entry] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return entries }
        return entries.filter { row in
            if String(localized: row.displayName).lowercased().contains(q) { return true }
            return row.effectiveShortcuts.contains { $0.displayString.lowercased().contains(q) }
        }
    }
}
