import AppKit
import Combine
import ShortcutKit

enum AppAction: String, ShortcutAction {
    case toggleLegend
    case closeWindow
    case openSettings
    case fireConfetti
    case openInspector
    case newProject

    var definition: ShortcutActionDefinition {
        switch self {
        case .toggleLegend: .init("Toggle Legend", Shortcut("cmd+h"))
        case .closeWindow: .init("Close Window", Shortcut("cmd+w"))
        case .openSettings: .init("Settings…", Shortcut("cmd+,"))
        case .fireConfetti: .init("Fire Confetti", Shortcut("cmd+shift+f"))
        case .openInspector: .init("Show Inspector", Shortcut("cmd+i"))
        case .newProject: .init("New Project…", Shortcut("cmd+n"))
        }
    }
}

@MainActor
final class AppContextModel: ObservableObject {
    @Published var legendVisible = true
    @Published var confettiTriggerCount = 0
    @Published var inspectorOpenSignal = 0
    @Published var newProjectSignal = 0
    let context: ShortcutContext<AppAction>

    init() {
        // Use a holder so the closure can reference `self` after `context` is set.
        let holder = ModelHolder()
        context = ShortcutContext<AppAction>("app") { action, _ in
            guard let target = holder.target else { return }
            switch action {
            case .toggleLegend:
                target.legendVisible.toggle()
            case .closeWindow:
                NSApp.keyWindow?.close()
            case .openSettings:
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            case .fireConfetti:
                target.confettiTriggerCount += 1
            case .openInspector:
                target.inspectorOpenSignal += 1
            case .newProject:
                target.newProjectSignal += 1
            }
        }
        holder.target = self
    }

    private final class ModelHolder {
        weak var target: AppContextModel?
    }
}
