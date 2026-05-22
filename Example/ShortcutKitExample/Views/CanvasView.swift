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

            // Render canvas objects positioned absolutely.
            ForEach(canvasModel.objects) { obj in
                objectView(obj)
                    .position(obj.position)
                    .onTapGesture { canvasModel.selectedObjectID = obj.id }
            }

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

    @ViewBuilder
    private func objectView(_ obj: CanvasObject) -> some View {
        let isSelected = canvasModel.selectedObjectID == obj.id
        switch obj.kind {
        case let .rectangle(size, fillIndex):
            Rectangle()
                .fill(CanvasPalette.color(at: fillIndex).opacity(0.7))
                .overlay(
                    Rectangle()
                        .stroke(isSelected ? Color.accentColor : Color.black.opacity(0.2),
                                lineWidth: isSelected ? 3 : 1)
                )
                .frame(width: size, height: size)
        case let .ellipse(size, fillIndex):
            Ellipse()
                .fill(CanvasPalette.color(at: fillIndex).opacity(0.7))
                .overlay(
                    Ellipse()
                        .stroke(isSelected ? Color.accentColor : Color.black.opacity(0.2),
                                lineWidth: isSelected ? 3 : 1)
                )
                .frame(width: size, height: size)
        case let .text(content, fontSize, bold):
            Text(content)
                .font(.system(size: fontSize, weight: bold ? .bold : .regular))
                .padding(6)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(isSelected ? Color.accentColor : Color.black.opacity(0.2),
                                lineWidth: isSelected ? 3 : 1)
                )
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
