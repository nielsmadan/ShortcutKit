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

        let registry = ShortcutRegistry(
            contexts: allContexts,
            mutuallyExclusiveContexts: [modeIDs, selectionIDs, wizardVsAll]
        )
        // Defaults are conflict-free; create the demo conflicts the way a user
        // would, via overrides, so the conflict UI has something to show.
        conflictDemo.seedConflicts()
        return registry
    }()
}

// MARK: - Conflict demo

/// Actions whose *defaults* are conflict-free — shipping colliding defaults would
/// trip ShortcutKit's developer guard (`checkDefaultLevelConflicts`) and trap. The
/// conflicts are instead created at runtime via `seedConflicts()`, exactly as an
/// end user would by re-binding two actions to the same key. That populates the
/// Settings tables and Diagnostics tab with real `duplicate` and `shadowedByGlobal`
/// badges, and "Clear stored overrides" makes them disappear.
enum ConflictDemoAction: String, ShortcutAction {
    case dupeA
    case dupeB
    case shadowed

    var definition: ShortcutActionDefinition {
        switch self {
        case .dupeA: .init("Duplicate A", Shortcut("cmd+ctrl+1"))
        case .dupeB: .init("Duplicate B", Shortcut("cmd+ctrl+2"))
        case .shadowed: .init("Shadowed by Global", Shortcut("ctrl+opt+cmd+j"))
        }
    }
}

@MainActor
final class ConflictDemoContextModel {
    let context: ShortcutContext<ConflictDemoAction>

    init() {
        context = ShortcutContext<ConflictDemoAction>("conflict.demo", displayName: "Conflict Demo")
    }

    /// Apply user-style overrides that collide on purpose: `dupeB` onto `dupeA`'s
    /// binding (a `duplicate` conflict), and `shadowed` onto the global hotkey
    /// (a `shadowedByGlobal` conflict, since the OS intercepts the global first).
    /// Called once after the registry is wired, so the conflict analyzer surfaces
    /// them. Idempotent — re-running sets the same overrides.
    func seedConflicts() {
        context.setShortcuts([Shortcut("cmd+ctrl+1")], for: .dupeB)
        context.setShortcuts([Shortcut("ctrl+opt+cmd+k")], for: .shadowed)
    }

    // Demo-only: the bindings exist to produce conflicts, not to do work. The
    // context isn't activated by any view, so these never fire.
    func handle(_: ConflictDemoAction, _: ShortcutDispatch) {}
}
