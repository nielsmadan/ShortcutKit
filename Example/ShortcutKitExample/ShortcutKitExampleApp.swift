import ShortcutKit
import ShortcutKitUI
import SwiftUI

@main
struct ShortcutKitExampleApp: App {
    @Environment(\.openWindow) private var openWindow
    @ObservedObject private var appModel = ContextWiring.app

    var body: some Scene {
        WindowGroup("ShortcutKit Example") {
            RootBridge(appModel: appModel)
        }
        WindowGroup("Inspector", id: "inspector") {
            InspectorWindowView()
                .environmentObject(ContextWiring.inspector)
        }
        Settings {
            ExampleSettingsView()
        }
    }
}

/// Wraps MainWindowView so the signal-driven `openWindow` and `openSettings`
/// environment values (which are only available inside a Scene's content
/// view) can react to AppContext shortcut dispatches.
@MainActor
private struct RootBridge: View {
    @ObservedObject var appModel: AppContextModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        MainWindowView()
            .shortcutHintHUD(registry: ContextWiring.shared)
            .onChange(of: appModel.inspectorOpenSignal) { _, _ in
                openWindow(id: "inspector")
            }
            .onChange(of: appModel.openSettingsSignal) { _, _ in
                try? openSettings()
            }
    }
}
