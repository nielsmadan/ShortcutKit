import Foundation
import ShortcutKit

enum ShapeSelectedAction: String, ShortcutAction {
    case sizeUp
    case sizeDown
    case cycleFill

    var definition: ShortcutActionDefinition {
        switch self {
        case .sizeUp: .init("Size Up", Shortcut("equal"))
        case .sizeDown: .init("Size Down", Shortcut("minus"))
        case .cycleFill: .init("Cycle Fill", Shortcut("f"))
        }
    }
}

enum TextSelectedAction: String, ShortcutAction {
    case fontSizeUp
    case fontSizeDown
    case toggleBold

    var definition: ShortcutActionDefinition {
        switch self {
        case .fontSizeUp: .init("Font Size Up", Shortcut("equal"))
        case .fontSizeDown: .init("Font Size Down", Shortcut("minus"))
        case .toggleBold: .init("Toggle Bold", Shortcut("b"))
        }
    }
}
