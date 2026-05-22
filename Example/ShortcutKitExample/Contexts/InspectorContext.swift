import Combine
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
        let holder = ModelHolder()
        context = ShortcutContext<InspectorAction>("inspector") { action, _ in
            guard let target = holder.target else { return }
            switch action {
            case .toggleLock:
                target.locked.toggle()
            case .resetTransform:
                ContextWiring.canvas.rotation = 0
            }
        }
        holder.target = self
    }

    private final class ModelHolder { weak var target: InspectorContextModel? }
}
