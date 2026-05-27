import ShortcutKit
import SwiftUI

@MainActor
struct InspectorWindowView: View {
    @EnvironmentObject var model: InspectorContextModel
    @ObservedObject var canvasModel = ContextWiring.canvas

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Locked", isOn: $model.locked)
            HStack {
                Text("Rotation:")
                Spacer()
                Text("\(Int(canvasModel.rotation))°")
                    .monospaced()
            }
            Spacer()
        }
        .padding()
        .frame(minWidth: 240, minHeight: 160)
        .activeShortcutContext(model.context, dispatch: model.handle)
    }
}
