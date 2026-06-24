import SwiftUI

/// How the legend lays its entries into columns.
public enum LegendColumns: Sendable, Hashable {
    /// One column — a vertical list.
    case single
    /// A fixed number of equal-width columns.
    case fixed(Int)
    /// As many equal columns as fit, each at least `minWidth` wide (adaptive).
    case auto(minWidth: CGFloat)
}

/// Order of the shortcut and the label within a legend cell.
public enum LegendEntryLayout: Sendable, Hashable {
    /// `⇧⌘L  Toggle Legend` — shortcut first. Compact; good for grids.
    case shortcutLeading
    /// `Toggle Legend ……… ⇧⌘L` — label first, shortcut trailing.
    case labelLeading
}

/// Layout knobs for `KeyBindingsLegendView`. The default is a compact,
/// content-sized, multi-column grid with the shortcut leading each cell. Tune
/// the column behavior, cell order, and font; pass per-action label overrides
/// via the view's `label:` closure (kept separate so this stays `Sendable`).
public struct LegendOptions: Sendable, Hashable {
    /// Column behavior. Default `.auto(minWidth: 150)`.
    public var columns: LegendColumns
    /// Shortcut-vs-label order in each cell. Default `.shortcutLeading`.
    public var entryLayout: LegendEntryLayout
    /// Point size for entry text (shortcut + label). Group headers use
    /// `fontSize + 2`. Default `10` (compact).
    public var fontSize: CGFloat

    public init(
        columns: LegendColumns = .auto(minWidth: 150),
        entryLayout: LegendEntryLayout = .shortcutLeading,
        fontSize: CGFloat = 10
    ) {
        self.columns = columns
        self.entryLayout = entryLayout
        self.fontSize = fontSize
    }

    public static let `default` = LegendOptions()
}

/// Resolves a `LegendColumns` choice to SwiftUI `GridItem`s for a `LazyVGrid`.
/// Factored out so the column mapping is unit-testable.
func legendGridItems(_ columns: LegendColumns) -> [GridItem] {
    switch columns {
    case .single:
        [GridItem(.flexible(), alignment: .topLeading)]
    case let .fixed(count):
        Array(repeating: GridItem(.flexible(), alignment: .topLeading), count: max(1, count))
    case let .auto(minWidth):
        [GridItem(.adaptive(minimum: minWidth), alignment: .topLeading)]
    }
}

/// Wrapping flow placement: positions cells left-to-right and wraps to a new row
/// when the next cell would exceed `maxWidth`. Returns each cell's origin plus the
/// total content size. Pure, so the compact legend's `Layout` can be unit-tested.
func legendFlowLayout(
    sizes: [CGSize],
    maxWidth: CGFloat,
    spacing: CGFloat,
    lineSpacing: CGFloat
) -> (size: CGSize, positions: [CGPoint]) {
    var positions: [CGPoint] = []
    var x: CGFloat = 0
    var y: CGFloat = 0
    var rowHeight: CGFloat = 0
    var contentWidth: CGFloat = 0
    for size in sizes {
        if x > 0, x + size.width > maxWidth {
            x = 0
            y += rowHeight + lineSpacing
            rowHeight = 0
        }
        positions.append(CGPoint(x: x, y: y))
        x += size.width + spacing
        rowHeight = max(rowHeight, size.height)
        contentWidth = max(contentWidth, x - spacing)
    }
    return (CGSize(width: contentWidth, height: y + rowHeight), positions)
}
