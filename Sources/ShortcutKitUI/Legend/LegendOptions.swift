import ShortcutField
import SwiftUI

/// How many columns of entries the (non-compact) legend lays out. Each entry is a
/// fixed-width cell (shortcut + label columns, sized from `LegendSize`), so entries
/// line up into true columns regardless of this choice.
public enum LegendColumns: Sendable, Hashable {
    /// One column — a vertical list. Ideal for a narrow docked rail.
    case single
    /// A fixed number of columns.
    case fixed(Int)
    /// As many cells as fit, wrapping to new rows. The default. `minWidth` is
    /// the per-cell floor — cells narrower than that are padded to `minWidth`
    /// before wrap placement, so callers can enforce a design rhythm.
    case auto(minWidth: CGFloat)
}

/// Horizontal sizing of the label column. `LegendSize` metrics remain the
/// default; `.flexible` and `.fixed(_)` let adopters override for one-column
/// rails, grid layouts, or design-specific widths. Cases mirror
/// `GridItem.Size`'s vocabulary (`fixed / flexible`) so SwiftUI callers see
/// familiar names.
public enum LegendLabelWidth: Sendable, Hashable {
    /// Use `LegendSize.metrics.labelWidth`. Default.
    case size
    /// Fill available horizontal space (`.frame(maxWidth: .infinity)`).
    case flexible
    /// Explicit width.
    case fixed(CGFloat)
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
                sectionSpacing: 16,
                shortcutWidth: 44,
                labelWidth: 110,
                gutter: 8
            )
        case .medium: LegendMetrics(
                entryFont: 12,
                headerFont: 11,
                rowSpacing: 6,
                columnSpacing: 14,
                headerToRows: 6,
                sectionSpacing: 19,
                shortcutWidth: 52,
                labelWidth: 130,
                gutter: 9
            )
        case .large: LegendMetrics(
                entryFont: 14,
                headerFont: 12,
                rowSpacing: 7,
                columnSpacing: 16,
                headerToRows: 7,
                sectionSpacing: 22,
                shortcutWidth: 60,
                labelWidth: 150,
                gutter: 10
            )
        case .extraLarge: LegendMetrics(
                entryFont: 17,
                headerFont: 14,
                rowSpacing: 9,
                columnSpacing: 20,
                headerToRows: 9,
                sectionSpacing: 27,
                shortcutWidth: 72,
                labelWidth: 180,
                gutter: 12
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
    /// Fixed width of the shortcut column (right-aligned, tail-truncated).
    let shortcutWidth: CGFloat
    /// Fixed width of the (wider) label column (left-aligned, tail-truncated).
    let labelWidth: CGFloat
    /// Gap between the shortcut and label columns within a cell.
    let gutter: CGFloat

    /// Total fixed width of one grouped legend cell (both columns + gutter).
    var cellWidth: CGFloat { shortcutWidth + gutter + labelWidth }
}

/// Layout knobs for `KeyBindingsLegendView`. The default is a grouped table of
/// fixed-width, aligned columns (shortcut then label) that wraps to fit. Tune the
/// column count, cell order, and overall size; pass per-action label overrides via
/// the view's `label:` closure (kept separate so this stays `Sendable`).
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
    /// How the shortcut portion of each entry renders. `nil` (the default) uses
    /// ShortcutField's ``ShortcutField/ShortcutLabelStyle/compact`` SF-symbol labels
    /// in both layouts — gestures/scroll become icons, mouse clicks abbreviations,
    /// each with a hover tooltip. Set ``ShortcutField/ShortcutLabelStyle/text`` to
    /// force verbose words instead.
    public var shortcutStyle: ShortcutLabelStyle?
    /// Label column width. Default `.size` uses the `LegendSize` metric; the
    /// `.single` column layout implicitly upgrades `.size` to `.flexible` so
    /// one-column rails breathe.
    public var labelWidth: LegendLabelWidth

    public init(
        columns: LegendColumns = .auto(minWidth: 150),
        entryLayout: LegendEntryLayout = .shortcutLeading,
        size: LegendSize = .small,
        compact: Bool = false,
        shortcutStyle: ShortcutLabelStyle? = nil,
        labelWidth: LegendLabelWidth = .size
    ) {
        self.columns = columns
        self.entryLayout = entryLayout
        self.size = size
        self.compact = compact
        self.shortcutStyle = shortcutStyle
        self.labelWidth = labelWidth
    }

    public static let `default` = LegendOptions()

    /// Resolved font sizes and spacings for `size`.
    var metrics: LegendMetrics { size.metrics }

    /// The resolved width of one grouped legend cell for these options — the sum
    /// of the shortcut column, gutter, and the *effective* label width (which may
    /// be a `.fixed(_)` override, not the `LegendSize` metric). Exposed so a host
    /// can size a container (e.g. a docked rail) to the legend without re-deriving
    /// the internal metrics. `.flexible` labels report the metric width as a floor.
    public var cellWidth: CGFloat { resolvedCellWidth(for: self) }
}

/// Width of one grouped legend cell for `options`, honoring a `.fixed(_)` label
/// override. `.flexible` reports the metric cell width (a sensible minimum, since
/// a flexible label grows to fill its container). Pure, so it's unit-testable and
/// the `.fixed(n)` grid and the label cell agree on a single width.
func resolvedCellWidth(for options: LegendOptions) -> CGFloat {
    let m = options.metrics
    switch effectiveLabelWidth(for: options) {
    case .size, .flexible:
        return m.cellWidth
    case let .fixed(width):
        return m.shortcutWidth + m.gutter + width
    }
}

/// Resolve the effective label width for `options`. When `columns == .single`
/// and `labelWidth == .size`, upgrade to `.flexible` — a one-column layout
/// wants to fill available space by default. Explicit overrides pass through.
/// Pure, so the smart-default rule is unit-testable.
func effectiveLabelWidth(for options: LegendOptions) -> LegendLabelWidth {
    if case .single = options.columns, options.labelWidth == .size {
        return .flexible
    }
    return options.labelWidth
}

/// Resolve the shortcut label style for a legend cell: an explicit `override`
/// wins, otherwise both layouts default to ShortcutField's `.compact` symbols.
/// Pure, so the default rule is unit-testable.
func legendShortcutStyle(override: ShortcutLabelStyle?) -> ShortcutLabelStyle {
    override ?? .compact
}

/// `count` fixed-width `GridItem`s for a `LazyVGrid` of fixed-size legend cells.
/// `count` is clamped to at least one. Factored out so the clamping is unit-testable.
/// (`.single` renders as a `VStack` and `.auto` flows via `legendFlowLayout`, so this
/// backs only the `.fixed(n)` arrangement.)
func legendGridItems(count: Int, cellWidth: CGFloat, spacing: CGFloat) -> [GridItem] {
    Array(
        repeating: GridItem(.fixed(cellWidth), spacing: spacing, alignment: .topLeading),
        count: max(1, count)
    )
}

/// `count` flexible `GridItem`s (minimum `minCellWidth`, no max) for a
/// `LazyVGrid` whose cells should grow to fill the container. Used when the
/// resolved label width is `.flexible` under a `.fixed(n)` column layout.
/// `count` clamps to at least one, matching `legendGridItems`.
func legendFlexibleGridItems(count: Int, minCellWidth: CGFloat, spacing: CGFloat) -> [GridItem] {
    Array(
        repeating: GridItem(.flexible(minimum: minCellWidth), spacing: spacing, alignment: .topLeading),
        count: max(1, count)
    )
}

/// Wrapping flow placement: positions cells left-to-right and wraps to a new row
/// when the next cell would exceed `maxWidth`. Returns each cell's origin and
/// constrained size plus the total content size. Any cell narrower than
/// `minCellWidth` is padded up to that floor before placement — that's how
/// `LegendColumns.auto(minWidth:)` enforces a
/// per-cell design rhythm. Pure, so the legend's `Layout` can be unit-tested.
func legendFlowLayout(
    sizes: [CGSize],
    maxWidth: CGFloat,
    spacing: CGFloat,
    lineSpacing: CGFloat,
    minCellWidth: CGFloat = 0
) -> (size: CGSize, positions: [CGPoint], itemSizes: [CGSize]) {
    var positions: [CGPoint] = []
    var itemSizes: [CGSize] = []
    var x: CGFloat = 0
    var y: CGFloat = 0
    var rowHeight: CGFloat = 0
    var contentWidth: CGFloat = 0
    for size in sizes {
        let itemSize = CGSize(width: min(max(size.width, minCellWidth), maxWidth), height: size.height)
        if x > 0, x + itemSize.width > maxWidth {
            x = 0
            y += rowHeight + lineSpacing
            rowHeight = 0
        }
        positions.append(CGPoint(x: x, y: y))
        itemSizes.append(itemSize)
        x += itemSize.width + spacing
        rowHeight = max(rowHeight, itemSize.height)
        contentWidth = max(contentWidth, x - spacing)
    }
    return (CGSize(width: contentWidth, height: y + rowHeight), positions, itemSizes)
}
