import ShortcutKit
import SwiftUI

@MainActor
public struct ContextPickerView: View {
    enum Style: Sendable { case segmented, dropdown }

    let contexts: [any AnyShortcutContext]
    @Binding var selection: String
    let conflictedIDs: Set<String>

    public init(
        contexts: [any AnyShortcutContext],
        selection: Binding<String>,
        conflictedIDs: Set<String>
    ) {
        self.contexts = contexts
        _selection = selection
        self.conflictedIDs = conflictedIDs
    }

    var visibleContexts: [any AnyShortcutContext] {
        contexts.filter(\.includeInSettings)
    }

    var pickerStyle: Style {
        visibleContexts.count <= 3 ? .segmented : .dropdown
    }

    func label(for ctx: any AnyShortcutContext) -> String {
        let prefix = ctx.scope == .global ? "🌐 " : ""
        return prefix + Self.displayName(forID: ctx.id)
    }

    /// Title-cases the context id for picker display. Splits on `.` so a
    /// dotted id like `canvas.shared` becomes `Canvas / Shared`. Adopters
    /// shouldn't have to embed display strings into the id since the id is
    /// the persistence key (stable forever).
    static func displayName(forID id: String) -> String {
        id.split(separator: ".")
            .map { segment -> String in
                let s = String(segment)
                guard let first = s.first else { return s }
                return first.uppercased() + s.dropFirst()
            }
            .joined(separator: " / ")
    }

    public var body: some View {
        Group {
            switch pickerStyle {
            case .segmented:
                Picker("Context", selection: $selection) { entries }
                    .pickerStyle(.segmented)
            case .dropdown:
                Picker("Context", selection: $selection) { entries }
                    .pickerStyle(.menu)
            }
        }
        .labelsHidden()
    }

    @ViewBuilder private var entries: some View {
        ForEach(visibleContexts, id: \.id) { ctx in
            HStack(spacing: 4) {
                Text(label(for: ctx))
                if conflictedIDs.contains(ctx.id) {
                    Circle().fill(.red).frame(width: 6, height: 6)
                }
            }.tag(ctx.id)
        }
    }
}
