import Combine
import Foundation
import ShortcutKit

enum InspectorAction: String, ShortcutAction {
    case toggleLock
    case resetTransform

    var definition: ShortcutActionDefinition {
        switch self {
        case .toggleLock: .init("Toggle Lock", Shortcut("cmd+d"))
        case .resetTransform: .init("Reset", Shortcut("cmd+r"))
        }
    }
}

@MainActor
final class InspectorContextModel: ObservableObject {
    @Published var locked = false
    let context: ShortcutContext<InspectorAction>

    init() {
        context = ShortcutContext<InspectorAction>("inspector")
    }

    func handle(_ action: InspectorAction, _: ShortcutDispatch) {
        switch action {
        case .toggleLock: locked.toggle()
        case .resetTransform: ContextWiring.canvas.rotation = 0
        }
    }
}
