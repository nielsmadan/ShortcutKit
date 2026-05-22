import ShortcutKit

@MainActor
enum ContextWiring {
    static let app = AppContextModel()
    static let sidebar = SidebarContextModel()
    static let canvas = CanvasModeContextModel()
    static let inspector = InspectorContextModel()
    static let wizard = WizardContextModel()

    static let shared: ShortcutRegistry = {
        let modeContexts: [any AnyShortcutContext] = CanvasMode.allCases.map { canvas.context(for: $0) }
        let allContexts: [any AnyShortcutContext] =
            [app.context, sidebar.context, inspector.context, wizard.context] + modeContexts

        // Two mutex sets:
        //   1. Canvas modes mutex each other (only one mode active at a time).
        //   2. Wizard masks everything else when active.
        let canvasModeMutex = Set(modeContexts.map(\.id))
        let wizardVsAll: Set<String> = Set(["wizard", "app", "sidebar", "inspector"])
            .union(canvasModeMutex)

        return ShortcutRegistry(
            contexts: allContexts,
            mutuallyExclusiveContexts: [canvasModeMutex, wizardVsAll],
            bindingsPerAction: .two
        )
    }()
}
