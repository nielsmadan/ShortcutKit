import AppKit
import Combine
import ShortcutKit

enum GlobalAction: String, ShortcutAction {
    case activateAndConfetti

    var definition: ShortcutActionDefinition {
        switch self {
        case .activateAndConfetti:
            // ⌃⌥⌘K — three modifiers, unlikely to collide with a system hotkey.
            .init("Activate + Confetti", Shortcut("ctrl+opt+cmd+k"))
        }
    }
}

@MainActor
final class GlobalContextModel: ObservableObject {
    let context: ShortcutContext<GlobalAction>

    init() {
        // Global contexts require their dispatch handler at construction —
        // they fire system-wide via Carbon whether or not any view is mounted,
        // so there's no activation hook to bind the handler later.
        context = ShortcutContext<GlobalAction>(global: "global") { action, _ in
            switch action {
            case .activateAndConfetti:
                NSApp.activate(ignoringOtherApps: true)
                ContextWiring.app.confettiTriggerCount += 1
            }
        }
    }
}
