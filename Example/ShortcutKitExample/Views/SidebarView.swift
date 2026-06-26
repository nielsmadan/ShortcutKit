import ShortcutKit
import ShortcutKitUI
import SwiftUI

@MainActor
struct SidebarView: View {
    @EnvironmentObject var model: SidebarContextModel

    var body: some View {
        VStack(spacing: 0) {
            List(selection: $model.selectedID) {
                ForEach(model.items) { item in
                    HStack {
                        Text(item.title)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                    .padding(.vertical, 2)
                    .padding(.horizontal, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(model.selectedID == item.id
                                ? Color.accentColor.opacity(0.35)
                                : Color.clear)
                    )
                    .tag(item.id)
                }
            }

            HStack {
                Button("+") { model.context.dispatch(.addItem) }
                Button("−") { model.context.dispatch(.removeItem) }
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)

            Divider()

            KeyBindingsLegendView(
                registry: ContextWiring.shared,
                style: .panel,
                contextIDs: [model.context.id]
            )
            .frame(maxHeight: 200)
        }
        .activeShortcutContext(model.context, dispatch: model.handle)
    }
}
