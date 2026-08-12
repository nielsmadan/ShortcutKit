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
        let modeContexts: [AnyShortcutContext] = [
            canvas.selectContext,
            canvas.fillContext,
            canvas.strokeContext,
            canvas.textContext,
            canvas.shapeContext,
        ]
        let modeIDs = Set(modeContexts.map(\.id))

        let selectionContexts: [AnyShortcutContext] = [
            canvas.shapeSelectedContext,
            canvas.textSelectedContext,
        ]
        let selectionIDs = Set(selectionContexts.map(\.id))

        let nonModeContexts: [AnyShortcutContext] = [
            app.context,
            sidebar.context,
            inspector.context,
            wizard.context,
            canvas.sharedContext,
            global.context,
            conflictDemo.context,
        ]

        let allContexts = nonModeContexts + modeContexts + selectionContexts

        // The wizard masks every canvas mode and selection context.
        let wizardVsAll: Set<String> = Set([
            "wizard", "app", "sidebar", "inspector", canvas.sharedContext.id,
        ])
        .union(modeIDs)
        .union(selectionIDs)

        let registry = ShortcutRegistry(
            contexts: allContexts,
            mutuallyExclusiveContexts: [modeIDs, selectionIDs, wizardVsAll],
            defaultHintFrequency: .always
        )
        // Default-level conflicts trap, so the demo creates user overrides instead.
        conflictDemo.seedConflicts()
        return registry
    }()
}

// MARK: - Conflict demo

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

    func seedConflicts() {
        context.setShortcuts([Shortcut("cmd+ctrl+1")], for: .dupeB)
        context.setShortcuts([Shortcut("ctrl+opt+cmd+k")], for: .shadowed)
    }

    func handle(_: ConflictDemoAction, _: ShortcutDispatch) {}
}
