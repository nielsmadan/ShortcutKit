import ShortcutField
import SwiftUI

/// Column layout for a non-compact legend.
public enum LegendColumns: Sendable, Hashable {
    /// One vertical column.
    case single
    /// A fixed number of columns.
    case fixed(Int)
    /// As many columns as fit, with a minimum cell width.
    case auto(minWidth: CGFloat)
}

/// Horizontal sizing for legend labels.
public enum LegendLabelWidth: Sendable, Hashable {
    /// Use the ``LegendSize`` width as a minimum, filling single and fixed-column layouts.
    case size
    /// Fill the available horizontal space.
    case flexible
    /// Explicit width.
    case fixed(CGFloat)
}

/// Order of the shortcut and the label within a legend cell.
public enum LegendEntryLayout: Sendable, Hashable {
    /// Shortcut first, for example `⇧⌘L  Toggle Legend`.
    case shortcutLeading
    /// Label first, for example `Toggle Legend  ⇧⌘L`.
    case labelLeading
}

/// Overall scale for legend fonts, columns, and spacing.
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
                rowSpacing: 2,
                columnSpacing: 12,
                headerToRows: 5,
                sectionSpacing: 16,
                shortcutWidth: 44,
                labelWidth: 110,
                gutter: 4
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
                gutter: 5
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
                gutter: 6
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
                gutter: 8
            )
        }
    }
}

struct LegendMetrics: Sendable, Hashable {
    let entryFont: CGFloat
    let headerFont: CGFloat
    let rowSpacing: CGFloat
    let columnSpacing: CGFloat
    let headerToRows: CGFloat
    let sectionSpacing: CGFloat
    let shortcutWidth: CGFloat
    let labelWidth: CGFloat
    let gutter: CGFloat

    var cellWidth: CGFloat { shortcutWidth + gutter + labelWidth }
}

/// Layout and appearance options for ``KeyBindingsLegendView``.
public struct LegendOptions: Sendable, Hashable {
    /// Column behavior. Default `.auto(minWidth: 150)`. Ignored when `compact`.
    public var columns: LegendColumns
    /// Shortcut-vs-label order in each cell. Default `.shortcutLeading`.
    public var entryLayout: LegendEntryLayout
    /// Overall font and spacing scale. Default `.small`.
    public var size: LegendSize
    /// Show a headerless, content-width strip instead of a grouped grid. Default `false`.
    public var compact: Bool
    /// Whether group headers show a divider. Default `true`.
    public var showsHeaderDivider: Bool
    /// Shortcut rendering style. `nil` uses ``ShortcutField/ShortcutLabelStyle/compact``.
    public var shortcutStyle: ShortcutLabelStyle?
    /// Label width. Default `.size` fills spare width in single- and fixed-column layouts.
    public var labelWidth: LegendLabelWidth
    /// Fonts and colors. Each field defaults to the built-in appearance.
    public var appearance: LegendAppearance

    public init(
        columns: LegendColumns = .auto(minWidth: 150),
        entryLayout: LegendEntryLayout = .shortcutLeading,
        size: LegendSize = .small,
        compact: Bool = false,
        showsHeaderDivider: Bool = true,
        shortcutStyle: ShortcutLabelStyle? = nil,
        labelWidth: LegendLabelWidth = .size,
        appearance: LegendAppearance = .default
    ) {
        self.columns = columns
        self.entryLayout = entryLayout
        self.size = size
        self.compact = compact
        self.showsHeaderDivider = showsHeaderDivider
        self.shortcutStyle = shortcutStyle
        self.labelWidth = labelWidth
        self.appearance = appearance
    }

    public static let `default` = LegendOptions()

    var metrics: LegendMetrics { size.metrics }

    /// Minimum width of a grouped entry cell, including its shortcut, gutter, and label.
    /// Flexible labels report their minimum width.
    public var cellWidth: CGFloat { resolvedCellWidth(for: self) }
}

func resolvedCellWidth(for options: LegendOptions) -> CGFloat {
    let widths = legendColumnWidths(for: options)
    switch effectiveLabelWidth(for: options) {
    case .size, .flexible:
        return widths.shortcut + options.metrics.gutter + widths.label
    case let .fixed(width):
        return widths.shortcut + options.metrics.gutter + width
    }
}

func legendColumnWidths(for options: LegendOptions) -> (shortcut: CGFloat, label: CGFloat) {
    let m = options.metrics
    let scale = legendColumnScale(for: options)
    return (m.shortcutWidth * scale, m.labelWidth * scale)
}

func legendColumnScale(for options: LegendOptions) -> CGFloat {
    let m = options.metrics
    let shortcut = options.appearance.shortcutNSFont(defaultSize: m.entryFont).pointSize
    let label = options.appearance.labelNSFont(defaultSize: m.entryFont).pointSize
    return max(max(shortcut, label) / m.entryFont, 1)
}

func effectiveLabelWidth(for options: LegendOptions) -> LegendLabelWidth {
    guard options.labelWidth == .size else { return options.labelWidth }
    switch options.columns {
    case .single, .fixed:
        return .flexible
    case .auto:
        return .size
    }
}

func legendShortcutStyle(override: ShortcutLabelStyle?) -> ShortcutLabelStyle {
    override ?? .compact
}

func legendGridItems(count: Int, cellWidth: CGFloat, spacing: CGFloat) -> [GridItem] {
    Array(
        repeating: GridItem(.fixed(cellWidth), spacing: spacing, alignment: .topLeading),
        count: max(1, count)
    )
}

func legendFlexibleGridItems(count: Int, minCellWidth: CGFloat, spacing: CGFloat) -> [GridItem] {
    Array(
        repeating: GridItem(.flexible(minimum: minCellWidth), spacing: spacing, alignment: .topLeading),
        count: max(1, count)
    )
}

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
