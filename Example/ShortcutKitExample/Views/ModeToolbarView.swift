import SwiftUI

@MainActor
struct ModeToolbarView: View {
    @EnvironmentObject var model: CanvasModeContextModel

    var body: some View {
        HStack(spacing: 4) {
            ForEach(CanvasMode.allCases, id: \.self) { mode in
                Button {
                    model.activeMode = mode
                } label: {
                    Text(mode.rawValue.capitalized)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(model.activeMode == mode ? Color.accentColor.opacity(0.3) : .clear)
                        .cornerRadius(4)
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .background(.bar)
    }
}
