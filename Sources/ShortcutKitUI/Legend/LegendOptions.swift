import SwiftUI

/// How the legend lays its entries into columns.
public enum LegendColumns: Sendable, Hashable {
    /// One column — a vertical list.
    case single
    /// A fixed number of equal-width columns.
    case fixed(Int)
    /// Content-sized cells that flow left-to-right and wrap, each at least
    /// `minWidth` wide so they line up into loose columns. The default — gives a
    /// tight, even-gapped grid that fills the width it's given without stretching.
    case auto(minWidth: CGFloat)
}

/// Order of the shortcut and the label within a legend cell.
public enum LegendEntryLayout: Sendable, Hashable {
    /// `⇧⌘L  Toggle Legend` — shortcut first. Compact; good for grids.
    case shortcutLeading
    /// `Toggle Legend ……… ⇧⌘L` — label first, shortcut trailing.
    case labelLeading
}

/// Overall legend scale. Drives the entry/header font sizes and all the spacing
/// derived from them, so one knob resizes the whole legend coherently.
public enum LegendSize: Sendable, Hashable, CaseIterable {
    case small
    case medium
    case large
    case extraLarge

    var metrics: LegendMetrics {
        switch self {
        case .small: LegendMetrics(
                entryFont: 10,
                headerFont: 9,
                rowSpacing: 5,
                columnSpacing: 12,
                headerToRows: 5,
                sectionSpacing: 16
            )
        case .medium: LegendMetrics(
                entryFont: 12,
                headerFont: 11,
                rowSpacing: 6,
                columnSpacing: 14,
                headerToRows: 6,
                sectionSpacing: 19
            )
        case .large: LegendMetrics(
                entryFont: 14,
                headerFont: 12,
                rowSpacing: 7,
                columnSpacing: 16,
                headerToRows: 7,
                sectionSpacing: 22
            )
        case .extraLarge: LegendMetrics(
                entryFont: 17,
                headerFont: 14,
                rowSpacing: 9,
                columnSpacing: 20,
                headerToRows: 9,
                sectionSpacing: 27
            )
        }
    }
}

/// Resolved point sizes / spacings for a `LegendSize`. `headerToRows` (header to
/// its own rows) is deliberately smaller than `sectionSpacing` (gap between
/// groups), so each header visually hugs the rows it labels.
struct LegendMetrics: Sendable, Hashable {
    let entryFont: CGFloat
    let headerFont: CGFloat
    let rowSpacing: CGFloat
    let columnSpacing: CGFloat
    let headerToRows: CGFloat
    let sectionSpacing: CGFloat
}

/// Layout knobs for `KeyBindingsLegendView`. The default is a compact,
/// content-sized, multi-column grid with the shortcut leading each cell. Tune
/// the column behavior, cell order, and overall size; pass per-action label
/// overrides via the view's `label:` closure (kept separate so this stays
/// `Sendable`).
public struct LegendOptions: Sendable, Hashable {
    /// Column behavior. Default `.auto(minWidth: 150)`. Ignored when `compact`.
    public var columns: LegendColumns
    /// Shortcut-vs-label order in each cell. Default `.shortcutLeading`.
    public var entryLayout: LegendEntryLayout
    /// Overall scale (font + spacing). Default `.small` (compact).
    public var size: LegendSize
    /// Collapse to the densest form: one continuous wrap of every entry, with no
    /// section headers and content-width cells (no column alignment). For a thin
    /// strip — a status bar, toolbar, or footer. Default `false` (grouped grid).
    public var compact: Bool

    public init(
        columns: LegendColumns = .auto(minWidth: 150),
        entryLayout: LegendEntryLayout = .shortcutLeading,
        size: LegendSize = .small,
        compact: Bool = false
    ) {
        self.columns = columns
        self.entryLayout = entryLayout
        self.size = size
        self.compact = compact
    }

    public static let `default` = LegendOptions()

    /// Resolved font sizes and spacings for `size`.
    var metrics: LegendMetrics { size.metrics }
}

/// Resolves a `LegendColumns` choice to SwiftUI `GridItem`s for a `LazyVGrid`.
/// Factored out so the column mapping is unit-testable. (`.auto` flows via
/// `legendFlowLayout` instead; this returns a single adaptive item for it so
/// callers that still grid it stay sensible.)
func legendGridItems(_ columns: LegendColumns, spacing: CGFloat = 8) -> [GridItem] {
    switch columns {
    case .single:
        [GridItem(.flexible(), spacing: spacing, alignment: .topLeading)]
    case let .fixed(count):
        Array(
            repeating: GridItem(.flexible(), spacing: spacing, alignment: .topLeading),
            count: max(1, count)
        )
    case let .auto(minWidth):
        [GridItem(.adaptive(minimum: minWidth), spacing: spacing, alignment: .topLeading)]
    }
}

/// Wrapping flow placement: positions cells left-to-right and wraps to a new row
/// when the next cell would exceed `maxWidth`. Returns each cell's origin plus the
/// total content size. Pure, so the legend's `Layout` can be unit-tested.
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
