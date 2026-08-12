import ShortcutKit
import ShortcutKitUI
import SwiftUI

@main
struct ShortcutKitExampleApp: App {
    @Environment(\.openWindow) private var openWindow
    @ObservedObject private var appModel = ContextWiring.app

    init() {
        ContextWiring.startGlobalActivator()
    }

    var body: some Scene {
        WindowGroup("ShortcutKit Example") {
            RootBridge(appModel: appModel)
        }
        .commands {
            CommandMenu("Actions") {
                Button("Toggle Legend") { ContextWiring.app.context.dispatch(.toggleLegend) }
                    .shortcut(.toggleLegend, in: ContextWiring.app.context)
                Button("Show Inspector") { ContextWiring.app.context.dispatch(.openInspector) }
                    .shortcut(.openInspector, in: ContextWiring.app.context)
                Button("New Project…") { ContextWiring.app.context.dispatch(.newProject) }
                    .shortcut(.newProject, in: ContextWiring.app.context)
                Button("Fire Confetti") { ContextWiring.app.context.dispatch(.fireConfetti) }
                    .shortcut(.fireConfetti, in: ContextWiring.app.context)
            }
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
