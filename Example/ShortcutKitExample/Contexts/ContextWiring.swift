import Foundation
import ShortcutKit
import ShortcutKitGlobal

@MainActor
enum ContextWiring {
    static let app = AppContextModel()
    static let sidebar = SidebarContextModel()
    static let canvas = CanvasModeContextModel()
    static let inspector = InspectorContextModel()
    static let wizard = WizardContextModel()
    static let global = GlobalContextModel()
    static let conflictDemo = ConflictDemoContextModel()

    /// The Carbon-backed global hotkey activator. Call `startGlobalActivator()`
    /// once at app launch.
    static let globalActivator = CarbonGlobalActivator()

    private static var globalActivatorStarted = false

    static func startGlobalActivator() {
        guard !globalActivatorStarted else { return }
        globalActivatorStarted = true
        do {
            try globalActivator.start(shared)
        } catch {
            assertionFailure("global activator failed to start: \(error)")
        }
    }

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
            global.context,
            conflictDemo.context,
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
            mutuallyExclusiveContexts: [modeIDs, selectionIDs, wizardVsAll]
        )
    }()
}

// MARK: - Conflict demo

/// Actions authored to deliberately collide, so the Settings tables and the
/// Diagnostics tab surface real conflict badges. `dupeA`/`dupeB` share a binding
/// (a `duplicate` conflict); `shadowed` reuses the global hotkey (a
/// `shadowedByGlobal` conflict, since the OS intercepts the global one first).
enum ConflictDemoAction: String, ShortcutAction {
    case dupeA
    case dupeB
    case shadowed

    var definition: ShortcutActionDefinition {
        switch self {
        case .dupeA: .init("Duplicate A", Shortcut("cmd+ctrl+1"))
        case .dupeB: .init("Duplicate B", Shortcut("cmd+ctrl+1"))
        case .shadowed: .init("Shadowed by Global", Shortcut("ctrl+opt+cmd+k"))
        }
    }
}

@MainActor
final class ConflictDemoContextModel {
    let context: ShortcutContext<ConflictDemoAction>

    init() {
        context = ShortcutContext<ConflictDemoAction>("conflict.demo", displayName: "Conflict Demo")
    }

    // Demo-only: the bindings exist to produce conflicts, not to do work. The
    // context isn't activated by any view, so these never fire.
    func handle(_: ConflictDemoAction, _: ShortcutDispatch) {}
}
