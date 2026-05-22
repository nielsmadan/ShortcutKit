import ShortcutKit
import ShortcutKitUI
import SwiftUI

@main
struct ShortcutKitExampleApp: App {
    @Environment(\.openWindow) private var openWindow
    @ObservedObject private var appModel = ContextWiring.app

    var body: some Scene {
        WindowGroup("ShortcutKit Example") {
            MainWindowView()
                .shortcutHintHUD(registry: ContextWiring.shared)
                .onChange(of: appModel.inspectorOpenSignal) { _, _ in
                    openWindow(id: "inspector")
                }
        }
        WindowGroup("Inspector", id: "inspector") {
            InspectorWindowView()
                .environmentObject(ContextWiring.inspector)
        }
        Settings {
            ShortcutPreferencesView(registry: ContextWiring.shared)
                .frame(width: 640, height: 480)
        }
    }
}
