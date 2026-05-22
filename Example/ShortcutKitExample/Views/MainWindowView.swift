import ShortcutKit
import ShortcutKitUI
import SwiftUI

@MainActor
struct MainWindowView: View {
    @ObservedObject var canvasModel = ContextWiring.canvas
    @ObservedObject var appModel = ContextWiring.app
    @ObservedObject var wizardModel = ContextWiring.wizard

    var body: some View {
        HStack(spacing: 0) {
            NavigationSplitView {
                SidebarView()
                    .environmentObject(ContextWiring.sidebar)
                    .navigationSplitViewColumnWidth(min: 200, ideal: 240)
            } detail: {
                VStack(spacing: 0) {
                    ModeToolbarView()
                        .environmentObject(canvasModel)
                    CanvasView()
                        .environmentObject(canvasModel)
                        .environmentObject(appModel)
                        .activeShortcutContext(canvasModel.context(for: canvasModel.activeMode))
                        .id(canvasModel.activeMode)
                }
            }

            if appModel.legendVisible {
                Divider()
                KeyBindingsLegendView(
                    legend: ContextWiring.shared.legend(for: visibleContextIDs),
                    style: .sidebar
                )
            }
        }
        .frame(minWidth: 800, minHeight: 600)
        .overlay {
            ActionToast(registry: ContextWiring.shared)
        }
        .sheet(isPresented: $wizardModel.visible) {
            NewProjectWizard()
                .environmentObject(wizardModel)
        }
        .onChange(of: appModel.newProjectSignal) { _, _ in
            wizardModel.start()
        }
    }

    /// Currently-visible contexts for the legend. Updates as active context changes.
    private var visibleContextIDs: Set<String> {
        Set([
            ContextWiring.app.context.id,
            ContextWiring.sidebar.context.id,
            canvasModel.context(for: canvasModel.activeMode).id,
        ])
    }
}
