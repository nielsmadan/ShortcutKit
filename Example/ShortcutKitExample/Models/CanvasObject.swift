import CoreGraphics
import Foundation
import SwiftUI

/// A drawable object on the canvas. Shapes (rectangle/ellipse) and text share
/// the same model so the canvas can render a heterogeneous list; selection-
/// driven shortcut contexts branch on `kind` to apply size/style adjustments.
struct CanvasObject: Identifiable, Hashable, Sendable {
    let id: UUID
    var position: CGPoint
    var kind: Kind

    enum Kind: Hashable, Sendable {
        case rectangle(size: Double, fillIndex: Int)
        case ellipse(size: Double, fillIndex: Int)
        case text(content: String, fontSize: Double, bold: Bool)
    }

    var isShape: Bool {
        if case .text = kind { false } else { true }
    }
}

/// Palette indexed by `fillIndex` (0=red, 1=blue, 2=green). Re-used by
/// `FillModeAction.applyN` and `ShapeSelectedAction.cycleFill`.
enum CanvasPalette {
    static let colors: [Color] = [.red, .blue, .green]
    static let count = colors.count

    static func color(at index: Int) -> Color {
        colors[((index % count) + count) % count]
    }
}
