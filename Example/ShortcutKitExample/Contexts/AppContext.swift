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
        case .toggleLegend: .init("Toggle Legend", Shortcut("cmd+shift+l"))
        case .closeWindow: .init("Close Window", Shortcut("cmd+w"))
        case .openSettings: .init("Settings…", Shortcut("cmd+comma"))
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
    @Published var openSettingsSignal = 0
    let context: ShortcutContext<AppAction>

    init() {
        context = ShortcutContext<AppAction>("app", displayName: "Application")
    }

    func handle(_ action: AppAction, _: ShortcutDispatch) {
        switch action {
        case .toggleLegend: legendVisible.toggle()
        case .closeWindow: NSApp.keyWindow?.close()
        case .openSettings: openSettingsSignal += 1
        case .fireConfetti: confettiTriggerCount += 1
        case .openInspector: inspectorOpenSignal += 1
        case .newProject: newProjectSignal += 1
        }
    }
}
