import CoreGraphics
import Foundation
import SwiftUI

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

enum CanvasPalette {
    static let colors: [Color] = [.red, .blue, .green]
    static let count = colors.count

    static func color(at index: Int) -> Color {
        colors[((index % count) + count) % count]
    }
}
