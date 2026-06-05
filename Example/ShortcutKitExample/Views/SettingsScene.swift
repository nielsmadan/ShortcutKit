import ShortcutKit
import ShortcutKitUI
import SwiftUI

/// The example app's Settings scene. Two tabs render the same `KeyBindingsView`
/// with different `KeyBindingsStyle`s side-by-side so adopters can compare the
/// flavors directly. The General toggle for hint visibility appears in both
/// tabs so it's always one click away.
@MainActor
struct ExampleSettingsView: View {
    var body: some View {
        TabView {
            StyledSettingsTab(style: .native)
                .tabItem { Label("Native", systemImage: "rectangle") }
            StyledSettingsTab(style: .dense)
                .tabItem { Label("Dense", systemImage: "rectangle.compress.vertical") }
        }
        .frame(width: 640, height: 520)
    }
}

@MainActor
private struct StyledSettingsTab: View {
    let style: KeyBindingsStyle
    @ObservedObject private var registry = ContextWiring.shared

    var body: some View {
        KeyBindingsView(registry: ContextWiring.shared, style: style)
            .safeAreaInset(edge: .top, spacing: 0) {
                displaySection
            }
    }

    /// Juggler-style "Display" group: a bold header above a single-row card
    /// containing the hints toggle, rendered as a pinned banner above the
    /// scrolling bindings list.
    private var displaySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Display")
                .font(.system(size: 14, weight: .semibold))
            HStack {
                Text("Show shortcut hints")
                Spacer()
                Toggle("", isOn: Binding(
                    get: { registry.hintsEnabled },
                    set: { registry.setHintsEnabled($0) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.gray.opacity(0.18),
                        in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.gray.opacity(0.25), lineWidth: 1)
            )
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
    }
}
