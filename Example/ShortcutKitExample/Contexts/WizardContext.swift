import Combine
import Foundation
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
        // includeInSettings: false — wizard context is hidden from the Settings picker.
        context = ShortcutContext<WizardAction>("wizard", includeInSettings: false)
    }

    func handle(_ action: WizardAction, _: ShortcutDispatch) {
        switch action {
        case .next:
            pageIndex = min(pageIndex + 1, pageCount - 1)
        case .previous:
            pageIndex = max(pageIndex - 1, 0)
        case .cancel:
            visible = false
            pageIndex = 0
        case .finish:
            if pageIndex == pageCount - 1 {
                visible = false
                pageIndex = 0
            } else {
                pageIndex += 1
            }
        }
    }

    func start() {
        pageIndex = 0
        visible = true
    }
}
