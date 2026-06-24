import Foundation
import ShortcutKit

/// Actions that work on the canvas regardless of which mode is active:
/// rotation gestures and add/select/delete commands over canvas objects.
enum CanvasSharedAction: String, ShortcutAction {
    case rotateRight
    case rotateLeft
    case addRectangle
    case addEllipse
    case addText
    case deleteSelected
    case selectNextObject
    case selectPreviousObject

    var definition: ShortcutActionDefinition {
        switch self {
        case .rotateRight:
            .init("Rotate Right", .continuous(.init(kind: .rotateClockwise, modifiers: [], sensitivity: 0.5)))
        case .rotateLeft:
            .init("Rotate Left", .continuous(.init(kind: .rotateCounterClockwise, modifiers: [], sensitivity: 0.5)))
        case .addRectangle: .init("Add Rectangle", Shortcut("r"))
        case .addEllipse: .init("Add Ellipse", Shortcut("e"))
        case .addText: .init("Add Text", Shortcut("t"))
        case .deleteSelected: .init("Delete Selected", Shortcut("delete"))
        case .selectNextObject: .init("Select Next Object", Shortcut("tab"))
        case .selectPreviousObject: .init("Select Previous Object", Shortcut("shift+tab"))
        }
    }
}
