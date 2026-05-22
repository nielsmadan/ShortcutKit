import Combine
import ShortcutKit

enum WizardAction: String, ShortcutAction {
    case next, previous, cancel, finish

    var definition: ShortcutActionDefinition {
        switch self {
        case .next: .init("Next", Shortcut("right"))
        case .previous: .init("Previous", Shortcut("left"))
        case .cancel: .init("Cancel", Shortcut("escape"))
        case .finish: .init("Finish", Shortcut("return"))
        }
    }
}

@MainActor
final class WizardContextModel: ObservableObject {
    @Published var visible = false
    @Published var pageIndex = 0
    let context: ShortcutContext<WizardAction>

    var pageCount: Int { 3 }

    init() {
        let holder = ModelHolder()
        // includeInSettings: false — wizard context is hidden from the Settings picker.
        context = ShortcutContext<WizardAction>(
            "wizard",
            includeInSettings: false
        ) { action, _ in
            guard let target = holder.target else { return }
            switch action {
            case .next:
                target.pageIndex = min(target.pageIndex + 1, target.pageCount - 1)
            case .previous:
                target.pageIndex = max(target.pageIndex - 1, 0)
            case .cancel:
                target.visible = false
                target.pageIndex = 0
            case .finish:
                if target.pageIndex == target.pageCount - 1 {
                    target.visible = false
                    target.pageIndex = 0
                } else {
                    target.pageIndex += 1
                }
            }
        }
        holder.target = self
    }

    func start() {
        pageIndex = 0
        visible = true
    }

    private final class ModelHolder {
        weak var target: WizardContextModel?
    }
}
