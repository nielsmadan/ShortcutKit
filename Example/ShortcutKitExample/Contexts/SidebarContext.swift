import Combine
import ShortcutKit

enum SidebarAction: String, ShortcutAction {
    case addItem, removeItem, focusItem1, focusItem2, focusItem3, selectNext, selectPrevious

    var definition: ShortcutActionDefinition {
        switch self {
        case .addItem: .init("Add Item", Shortcut("cmd+equal"))
        case .removeItem: .init("Remove Item", Shortcut("cmd+minus"))
        case .focusItem1: .init("Focus #1", Shortcut("cmd+1"))
        case .focusItem2: .init("Focus #2", Shortcut("cmd+2"))
        case .focusItem3: .init("Focus #3", Shortcut("cmd+3"))
        case .selectNext: .init("Next Layer", Shortcut("j"))
        case .selectPrevious: .init("Previous Layer", Shortcut("k"))
        }
    }
}

@MainActor
final class SidebarContextModel: ObservableObject {
    @Published var items: [ListItem] = [ListItem(title: "Layer 1")]
    @Published var selectedID: ListItem.ID?
    let context: ShortcutContext<SidebarAction>

    init() {
        let holder = ModelHolder()
        context = ShortcutContext<SidebarAction>("sidebar") { action, _ in
            guard let target = holder.target else { return }
            switch action {
            case .addItem:
                target.items.append(.init(title: "Layer \(target.items.count + 1)"))
            case .removeItem:
                if let id = target.selectedID {
                    target.items.removeAll { $0.id == id }
                    target.selectedID = target.items.first?.id
                }
            case .focusItem1: target.selectedID = target.items[safe: 0]?.id
            case .focusItem2: target.selectedID = target.items[safe: 1]?.id
            case .focusItem3: target.selectedID = target.items[safe: 2]?.id
            case .selectNext: target.moveSelection(by: 1)
            case .selectPrevious: target.moveSelection(by: -1)
            }
        }
        holder.target = self
    }

    private final class ModelHolder {
        weak var target: SidebarContextModel?
    }

    /// Move the selection by `delta` positions, clamped to the items' bounds.
    /// If nothing is selected, jumps to the first (delta > 0) or last (delta < 0).
    func moveSelection(by delta: Int) {
        guard !items.isEmpty else { return }
        let currentIndex = items.firstIndex { $0.id == selectedID }
        let nextIndex: Int = if let currentIndex {
            (currentIndex + delta).clamped(to: 0 ... items.count - 1)
        } else {
            delta > 0 ? 0 : items.count - 1
        }
        selectedID = items[nextIndex].id
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
