import ShortcutKit
import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(spacing: 12) {
            Text("ShortcutKitExample")
                .font(.title2)
            Text("Phase 1 in progress — bindings demo grows as tasks land.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(width: 480, height: 200)
        .padding()
    }
}

#Preview { ContentView() }
