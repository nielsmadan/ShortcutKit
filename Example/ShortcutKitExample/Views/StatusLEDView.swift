import SwiftUI

@MainActor
struct StatusLEDView: View {
    let pulseCount: Int
    @State private var scale: CGFloat = 1.0
    @State private var opacity: Double = 1.0

    var body: some View {
        Circle()
            .fill(.orange)
            .frame(width: 12, height: 12)
            .scaleEffect(scale)
            .opacity(opacity)
            .onChange(of: pulseCount) { _, _ in
                pulse()
            }
    }

    private func pulse() {
        withAnimation(.easeOut(duration: 0.05)) {
            scale = 1.8
            opacity = 0.4
        }
        withAnimation(.easeIn(duration: 0.15).delay(0.05)) {
            scale = 1.0
            opacity = 1.0
        }
    }
}
