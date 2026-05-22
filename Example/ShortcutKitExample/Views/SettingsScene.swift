import ShortcutKit
import ShortcutKitUI
import SwiftUI

/// The example app's Settings scene. Two tabs render the same `KeyBindingsView`
/// with different `ShortcutStyle`s side-by-side so adopters can compare the
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
    let style: ShortcutStyle
    @AppStorage(ShortcutPreferencesView.hintsEnabledStorageKey)
    private var hintsEnabled = true

    var body: some View {
        Form {
            Section("General") {
                Toggle("Show shortcut hints", isOn: $hintsEnabled)
            }
            Section("Shortcuts") {
                KeyBindingsView(registry: ContextWiring.shared)
                    .shortcutStyle(style)
            }
        }
    }
}
