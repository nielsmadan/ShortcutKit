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
    }

    @Test func sizeVariantsScaleUp() {
        let fonts = LegendSize.allCases.map { LegendOptions(size: $0).metrics.entryFont }
        #expect(fonts == fonts.sorted()) // small → extraLarge is monotonically larger
        #expect(Set(fonts).count == LegendSize.allCases.count) // every size is distinct
        // Each header hugs its rows: header-to-rows gap stays below the gap
        // between sections, at every size.
        for size in LegendSize.allCases {
            let m = size.metrics
            #expect(m.headerToRows < m.sectionSpacing)
        }
    }

    @Test func columnsResolveToGridItemCounts() {
        #expect(legendGridItems(.single).count == 1)
        #expect(legendGridItems(.fixed(3)).count == 3)
        #expect(legendGridItems(.fixed(0)).count == 1) // clamped to at least one
        #expect(legendGridItems(.auto(minWidth: 120)).count == 1) // one adaptive item
    }

    @Test func flowLayoutWrapsWhenNarrow() {
        let sizes = Array(repeating: CGSize(width: 100, height: 20), count: 3)
        let result = legendFlowLayout(sizes: sizes, maxWidth: 250, spacing: 10, lineSpacing: 5)
        // c0 at (0,0); c1 at (110,0) since 110+100 ≤ 250; c2 overflows → wraps to (0,25).
        #expect(result.positions[0] == CGPoint(x: 0, y: 0))
        #expect(result.positions[1] == CGPoint(x: 110, y: 0))
        #expect(result.positions[2] == CGPoint(x: 0, y: 25))
        #expect(result.size.height == 45) // two rows: 20 + 5 + 20
    }

    @Test func flowLayoutSingleRowWhenWide() {
        let sizes = Array(repeating: CGSize(width: 50, height: 20), count: 4)
        let result = legendFlowLayout(sizes: sizes, maxWidth: 1000, spacing: 10, lineSpacing: 5)
        #expect(result.positions.allSatisfy { $0.y == 0 }) // all on one row
        #expect(result.size.height == 20)
    }
}
