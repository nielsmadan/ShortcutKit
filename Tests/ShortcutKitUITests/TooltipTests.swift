import AppKit
import CoreGraphics
@testable import ShortcutKitUI
import Testing

@MainActor
struct TooltipTests {
    @Test func isTruncated_shortStringFits() {
        #expect(legendTextIsTruncated(" ", font: .systemFont(ofSize: 10), width: 500) == false)
    }

    @Test func isTruncated_longStringOverflows() {
        let long = String(repeating: "abc ", count: 50)
        #expect(legendTextIsTruncated(long, font: .systemFont(ofSize: 12), width: 50) == true)
    }

    @Test func isTruncated_emptyStringNeverTruncates() {
        #expect(legendTextIsTruncated("", font: .systemFont(ofSize: 12), width: 100) == false)
        #expect(legendTextIsTruncated("", font: .systemFont(ofSize: 12), width: 0) == false)
    }

    @Test func isTruncated_zeroWidthReturnsFalse() {
        // Zero width occurs before the first layout measurement.
        #expect(legendTextIsTruncated("anything", font: .systemFont(ofSize: 12), width: 0) == false)
    }

    @Test func isTruncated_transitionsAtOwnWidth() {
        // Runtime measurement avoids pinning font metrics that vary across macOS versions.
        let text = "Toggle Diagnostics Overlay"
        let w = (text as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 12)]).width
        #expect(legendTextIsTruncated(text, font: .systemFont(ofSize: 12), width: w) == false)
        #expect(legendTextIsTruncated(text, font: .systemFont(ofSize: 12), width: w - 1) == true)
    }

    @Test func isTruncated_monospacedIsAValidGate() {
        let mono = LegendAppearance.default.shortcutNSFont(defaultSize: 12)
        #expect(legendTextIsTruncated("Command K", font: mono, width: 1) == true)
        #expect(legendTextIsTruncated("Command K", font: mono, width: 500) == false)
    }

    @Test func legendTooltipText_nilDescriptionReturnsNil() {
        #expect(legendTooltipText(label: "Show Monitor", description: nil) == nil)
    }

    @Test func legendTooltipText_composesLabelAndDescription() {
        #expect(
            legendTooltipText(label: "Show Monitor", description: "Cycles through views")
                == "Show Monitor — Cycles through views"
        )
    }
}
