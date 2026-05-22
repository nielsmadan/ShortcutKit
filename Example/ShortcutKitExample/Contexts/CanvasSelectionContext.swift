import ShortcutKit

/// Active when a shape (rectangle/ellipse) is selected. The `=` and `-` keys
/// resize the shape and `f` cycles through the fill palette — the same
/// chord can be bound here and in `TextSelectedAction` because only one of
/// the two contexts is active at a time (Photoshop-style mode-by-selection).
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

/// Active when a text object is selected.
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
