import ShortcutKit

@MainActor
enum ContextWiring {
    static let app = AppContextModel()
    static let sidebar = SidebarContextModel()
    static let canvas = CanvasModeContextModel()
    static let inspector = InspectorContextModel()
    static let wizard = WizardContextModel()

    static let shared: ShortcutRegistry = {
        // Per-mode contexts: heterogeneous (each has its own Action type) but
        // collected through the existential `any AnyShortcutContext`.
        let modeContexts: [any AnyShortcutContext] = [
            canvas.selectContext,
            canvas.fillContext,
            canvas.strokeContext,
            canvas.textContext,
            canvas.shapeContext,
        ]
        let modeIDs = Set(modeContexts.map(\.id))

        // Selection-driven contexts (only one is active at a time, gated by the
        // selected object's kind).
        let selectionContexts: [any AnyShortcutContext] = [
            canvas.shapeSelectedContext,
            canvas.textSelectedContext,
        ]
        let selectionIDs = Set(selectionContexts.map(\.id))

        let nonModeContexts: [any AnyShortcutContext] = [
            app.context,
            sidebar.context,
            inspector.context,
            wizard.context,
            canvas.sharedContext,
        ]

        let allContexts = nonModeContexts + modeContexts + selectionContexts

        // Mutex sets:
        //   1. The five canvas modes (only one mode active at a time).
        //   2. Shape-selected vs text-selected (only one selection type).
        //   3. Wizard masks everything else when active.
        let wizardVsAll: Set<String> = Set([
            "wizard", "app", "sidebar", "inspector", canvas.sharedContext.id,
        ])
        .union(modeIDs)
        .union(selectionIDs)

        return ShortcutRegistry(
            contexts: allContexts,
            mutuallyExclusiveContexts: [modeIDs, selectionIDs, wizardVsAll],
            bindingsPerAction: .two
        )
    }()
}
