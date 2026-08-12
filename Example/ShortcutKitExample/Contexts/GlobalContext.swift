import AppKit
import Combine
import ShortcutKit

enum GlobalAction: String, ShortcutAction {
    case activateAndConfetti

    var definition: ShortcutActionDefinition {
        switch self {
        case .activateAndConfetti:
            .init("Activate + Confetti", Shortcut("ctrl+opt+cmd+k"))
        }
    }
}

@MainActor
final class GlobalContextModel: ObservableObject {
    let context: ShortcutContext<GlobalAction>

    init() {
        // Global actions can fire without a mounted view, so they bind here.
        context = ShortcutContext<GlobalAction>(global: "global") { action, _ in
            switch action {
            case .activateAndConfetti:
                NSApp.activate(ignoringOtherApps: true)
                ContextWiring.app.confettiTriggerCount += 1
            }
        }
    }
}
