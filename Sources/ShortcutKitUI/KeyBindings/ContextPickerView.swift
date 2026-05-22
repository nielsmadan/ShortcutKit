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
        return prefix + ctx.id
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
