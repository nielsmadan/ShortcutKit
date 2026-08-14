import CoreGraphics
@testable import ShortcutKitUI
import Testing

@MainActor
struct LegendOptionsTests {
    @Test func defaultIsCompactAutoGrid() {
        let options = LegendOptions.default
        #expect(options.columns == .auto(minWidth: 150))
        #expect(options.entryLayout == .shortcutLeading)
        #expect(options.size == .small)
        #expect(options.metrics.entryFont == 10)
        #expect(options.shortcutStyle == nil)
    }

    @Test func shortcutStyleDefaultsToCompact() {
        #expect(legendShortcutStyle(override: nil) == .compact)
    }

    @Test func shortcutStyleOverrideWins() {
        #expect(legendShortcutStyle(override: .text) == .text)
        #expect(legendShortcutStyle(override: .compact) == .compact)
    }

    @Test func sizeVariantsScaleUp() {
        let fonts = LegendSize.allCases.map { LegendOptions(size: $0).metrics.entryFont }
        #expect(fonts == fonts.sorted())
        #expect(Set(fonts).count == LegendSize.allCases.count)
        for size in LegendSize.allCases {
            let m = size.metrics
            #expect(m.headerToRows < m.sectionSpacing)
        }
    }

    @Test func smallPresetKeepsRowsDense() {
        let options = LegendOptions.default
        let result = legendFlowLayout(
            sizes: [CGSize(width: 100, height: 20), CGSize(width: 100, height: 20)],
            maxWidth: 100,
            spacing: options.metrics.columnSpacing,
            lineSpacing: options.metrics.rowSpacing
        )

        #expect(result.positions[1].y == 22)
    }

    @Test func mediumPresetUsesFourPointRowSpacing() {
        let options = LegendOptions(size: .medium)
        let result = legendFlowLayout(
            sizes: [CGSize(width: 100, height: 20), CGSize(width: 100, height: 20)],
            maxWidth: 100,
            spacing: options.metrics.columnSpacing,
            lineSpacing: options.metrics.rowSpacing
        )

        #expect(result.positions[1].y == 24)
    }

    @Test func headerDividerCanBeHidden() {
        var options = LegendOptions.default
        #expect(legendHeaderDividerOpacity(for: options) == 0.6)

        options.showsHeaderDivider = false
        #expect(legendHeaderDividerOpacity(for: options) == 0)
    }

    @Test func columnWidthsScaleWithSize() {
        let shortcutWidths = LegendSize.allCases.map(\.metrics.shortcutWidth)
        #expect(shortcutWidths == [44, 52, 60, 72])
        let gutters = LegendSize.allCases.map(\.metrics.gutter)
        #expect(gutters == [4, 5, 6, 8])
        let widths = LegendSize.allCases.map(\.metrics.cellWidth)
        #expect(widths == widths.sorted())
        #expect(Set(widths).count == LegendSize.allCases.count)
        for size in LegendSize.allCases {
            let m = size.metrics
            #expect(m.labelWidth > m.shortcutWidth)
        }
    }

    @Test func resolvedCellWidthHonorsFixedLabelOverride() {
        let m = LegendSize.small.metrics
        let sized = LegendOptions(columns: .fixed(2), size: .small, labelWidth: .size)
        #expect(resolvedCellWidth(for: sized) == m.cellWidth)
        #expect(sized.cellWidth == m.cellWidth)
        let fixed = LegendOptions(columns: .fixed(2), size: .small, labelWidth: .fixed(240))
        #expect(resolvedCellWidth(for: fixed) == m.shortcutWidth + m.gutter + 240)
        #expect(fixed.cellWidth > m.cellWidth)
    }

    @Test func fixedColumnCountClamps() {
        #expect(legendGridItems(count: 3, cellWidth: 200, spacing: 8).count == 3)
        #expect(legendGridItems(count: 1, cellWidth: 200, spacing: 8).count == 1)
        #expect(legendGridItems(count: 0, cellWidth: 200, spacing: 8).count == 1)
    }

    @Test func flowLayoutWrapsWhenNarrow() {
        let sizes = Array(repeating: CGSize(width: 100, height: 20), count: 3)
        let result = legendFlowLayout(sizes: sizes, maxWidth: 250, spacing: 10, lineSpacing: 5)
        #expect(result.positions[0] == CGPoint(x: 0, y: 0))
        #expect(result.positions[1] == CGPoint(x: 110, y: 0))
        #expect(result.positions[2] == CGPoint(x: 0, y: 25))
        #expect(result.size.height == 45)
    }

    @Test func flowLayoutSingleRowWhenWide() {
        let sizes = Array(repeating: CGSize(width: 50, height: 20), count: 4)
        let result = legendFlowLayout(sizes: sizes, maxWidth: 1000, spacing: 10, lineSpacing: 5)
        #expect(result.positions.allSatisfy { $0.y == 0 })
        #expect(result.size.height == 20)
    }

    @Test func flowLayoutClampsCellWiderThanAvailableWidth() {
        let sizes = [CGSize(width: 300, height: 20), CGSize(width: 50, height: 20)]
        let result = legendFlowLayout(sizes: sizes, maxWidth: 200, spacing: 10, lineSpacing: 5)
        #expect(result.size.width == 200)
        #expect(result.positions[1] == CGPoint(x: 0, y: 25))
    }

    @Test func flowLayoutRespectsMinCellWidth() {
        let sizes = [CGSize(width: 30, height: 20), CGSize(width: 150, height: 20)]
        let result = legendFlowLayout(
            sizes: sizes, maxWidth: 1000, spacing: 10, lineSpacing: 5, minCellWidth: 100
        )
        #expect(result.positions[0] == CGPoint(x: 0, y: 0))
        #expect(result.positions[1] == CGPoint(x: 110, y: 0))
    }

    @Test func flowLayoutMinCellWidthDefaultsToNoFloor() {
        let sizes = [CGSize(width: 30, height: 20), CGSize(width: 30, height: 20)]
        let result = legendFlowLayout(sizes: sizes, maxWidth: 1000, spacing: 10, lineSpacing: 5)
        #expect(result.positions[1].x == 40)
    }

    @Test func labelWidthDefaultsToSize() {
        #expect(LegendOptions().labelWidth == .size)
    }

    @Test func effectiveLabelWidth_singleColumnUpgradesSizeToFlexible() {
        let opts = LegendOptions(columns: .single, labelWidth: .size)
        #expect(effectiveLabelWidth(for: opts) == .flexible)
    }

    @Test func effectiveLabelWidth_singleColumnRespectsExplicitFixed() {
        let opts = LegendOptions(columns: .single, labelWidth: .fixed(180))
        #expect(effectiveLabelWidth(for: opts) == .fixed(180))
    }

    @Test func effectiveLabelWidth_singleColumnRespectsExplicitFlexible() {
        let opts = LegendOptions(columns: .single, labelWidth: .flexible)
        #expect(effectiveLabelWidth(for: opts) == .flexible)
    }

    @Test func effectiveLabelWidth_fixedColumnsUpgradeSizeToFlexible() {
        let opts = LegendOptions(columns: .fixed(3), labelWidth: .size)
        #expect(effectiveLabelWidth(for: opts) == .flexible)
    }

    @Test func effectiveLabelWidth_autoColumnsKeepSize() {
        let opts = LegendOptions(columns: .auto(minWidth: 200), labelWidth: .size)
        #expect(effectiveLabelWidth(for: opts) == .size)
    }

    @Test func flexibleGridItemsClampsCount() {
        #expect(legendFlexibleGridItems(count: 3, minCellWidth: 200, spacing: 8).count == 3)
        #expect(legendFlexibleGridItems(count: 1, minCellWidth: 200, spacing: 8).count == 1)
        #expect(legendFlexibleGridItems(count: 0, minCellWidth: 200, spacing: 8).count == 1)
    }
}
