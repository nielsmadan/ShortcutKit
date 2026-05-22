import SwiftUI

@MainActor
struct ConfettiOverlay: View {
    let triggerCount: Int
    @State private var particles: [Particle] = []

    var body: some View {
        ZStack {
            ForEach(particles) { particle in
                Circle()
                    .fill(particle.color)
                    .frame(width: particle.size, height: particle.size)
                    .position(particle.position)
                    .opacity(particle.opacity)
            }
        }
        .allowsHitTesting(false)
        .onChange(of: triggerCount) { _, newCount in
            guard newCount > 0 else { return }
            burst()
        }
    }

    private func burst() {
        let bounds = CGSize(width: 600, height: 400)
        var fresh: [Particle] = []
        for _ in 0 ..< 30 {
            let start = CGPoint(x: bounds.width / 2, y: bounds.height / 2)
            let end = CGPoint(
                x: bounds.width / 2 + CGFloat.random(in: -300 ... 300),
                y: bounds.height / 2 + CGFloat.random(in: -200 ... 200)
            )
            let particle = Particle(
                id: UUID(),
                color: Color(
                    red: .random(in: 0 ... 1),
                    green: .random(in: 0 ... 1),
                    blue: .random(in: 0 ... 1)
                ),
                size: .random(in: 4 ... 10),
                position: start,
                opacity: 1.0,
                end: end
            )
            fresh.append(particle)
        }
        particles.append(contentsOf: fresh)

        // Animate fresh particles to end positions + fade out.
        for index in particles.indices.suffix(fresh.count) {
            let target = particles[index].end
            withAnimation(.easeOut(duration: 0.6)) {
                particles[index].position = target
                particles[index].opacity = 0
            }
        }

        // Clean up after the animation completes.
        Task {
            try? await Task.sleep(for: .seconds(0.7))
            particles.removeAll { $0.opacity == 0 }
        }
    }
}

private struct Particle: Identifiable {
    let id: UUID
    let color: Color
    let size: CGFloat
    var position: CGPoint
    var opacity: Double
    let end: CGPoint
}
