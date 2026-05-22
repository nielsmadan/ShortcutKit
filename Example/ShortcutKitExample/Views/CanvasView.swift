import SwiftUI

@MainActor
struct CanvasView: View {
    @EnvironmentObject var canvasModel: CanvasModeContextModel
    @EnvironmentObject var appModel: AppContextModel

    var body: some View {
        ZStack {
            Rectangle()
                .fill(color(for: canvasModel.activeMode))
            Text("Canvas — \(canvasModel.activeMode.rawValue.capitalized) mode")
                .font(.title)
                .foregroundStyle(.secondary)
            VStack {
                Spacer()
                SpinnerView()
                Spacer()
            }
            VStack {
                HStack {
                    Spacer()
                    StatusLEDView(pulseCount: canvasModel.statusLEDPulse)
                        .padding()
                }
                Spacer()
            }
            ConfettiOverlay(triggerCount: appModel.confettiTriggerCount)
        }
    }

    private func color(for mode: CanvasMode) -> Color {
        switch mode {
        case .select: Color(white: 0.95)
        case .fill: Color.yellow.opacity(0.3)
        case .stroke: Color.blue.opacity(0.3)
        case .text: Color.green.opacity(0.3)
        case .shape: Color.pink.opacity(0.3)
        }
    }
}
