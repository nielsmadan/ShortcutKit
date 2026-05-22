import SwiftUI

@MainActor
struct SpinnerView: View {
    @EnvironmentObject var canvasModel: CanvasModeContextModel

    var body: some View {
        Image(systemName: "triangle.fill")
            .resizable()
            .frame(width: 60, height: 60)
            .foregroundStyle(.purple)
            .rotationEffect(.degrees(canvasModel.rotation))
            .animation(.linear(duration: 0.1), value: canvasModel.rotation)
    }
}
