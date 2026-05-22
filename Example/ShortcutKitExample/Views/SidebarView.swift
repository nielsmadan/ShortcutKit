import ShortcutKit
import SwiftUI

@MainActor
struct SidebarView: View {
    @EnvironmentObject var model: SidebarContextModel

    var body: some View {
        VStack {
            List(model.items, selection: $model.selectedID) { item in
                Text(item.title)
            }
            HStack {
                Button("+") { model.context.dispatch(.addItem) }
                Button("−") { model.context.dispatch(.removeItem) }
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
        }
        .activeShortcutContext(model.context)
    }
}
