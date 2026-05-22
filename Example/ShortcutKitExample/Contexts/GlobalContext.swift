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
        // Use a holder so the closure can reference `self` after `context` is set.
        let holder = ModelHolder()
        context = ShortcutContext<GlobalAction>("global", scope: .global) { action, _ in
            guard holder.target != nil else { return }
            switch action {
            case .activateAndConfetti:
                NSApp.activate(ignoringOtherApps: true)
                ContextWiring.app.confettiTriggerCount += 1
            }
        }
        holder.target = self
    }

    private final class ModelHolder {
        weak var target: GlobalContextModel?
    }
}
