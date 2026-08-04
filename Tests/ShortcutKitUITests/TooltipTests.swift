import AppKit
import CoreGraphics
@testable import ShortcutKitUI
import Testing

@MainActor
struct TooltipTests {
    // Font size + width chosen so measurement is well-defined without depending
    // on exact system-font metrics; assertions bracket the boundary rather than
    // pinning it, since `NSAttributedString.size` isn't a fixed constant across
    // OS versions.

    @Test func isTruncated_shortStringFits() {
        // A single space at 10pt is nowhere near 500pt wide.
        #expect(legendTextIsTruncated(" ", font: .systemFont(ofSize: 10), width: 500) == false)
    }

    @Test func isTruncated_longStringOverflows() {
        // A 200-char string at 12pt easily exceeds a 50pt frame.
        let long = String(repeating: "abc ", count: 50)
        #expect(legendTextIsTruncated(long, font: .systemFont(ofSize: 12), width: 50) == true)
    }

    @Test func isTruncated_emptyStringNeverTruncates() {
        #expect(legendTextIsTruncated("", font: .systemFont(ofSize: 12), width: 100) == false)
        #expect(legendTextIsTruncated("", font: .systemFont(ofSize: 12), width: 0) == false)
    }

    @Test func isTruncated_zeroWidthReturnsFalse() {
        // Guard: no meaningful "does it fit" answer for a zero-width frame —
        // treat as not-truncated so we don't fire tooltips during initial layout
        // before `frameWidth` is measured.
        #expect(legendTextIsTruncated("anything", font: .systemFont(ofSize: 12), width: 0) == false)
    }

    @Test func isTruncated_transitionsAtOwnWidth() {
        // Derive the string's own rendered width via the same measurement path,
        // then bracket the strict `>` gate: it fits at exactly its own width and
        // truncates just below. OS-version-independent (expected width is measured,
        // not pinned), and unlike the old test it exercises the fit→truncate flip.
        let text = "Toggle Diagnostics Overlay"
        let w = (text as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 12)]).width
        #expect(legendTextIsTruncated(text, font: .systemFont(ofSize: 12), width: w) == false)
        #expect(legendTextIsTruncated(text, font: .systemFont(ofSize: 12), width: w - 1) == true)
    }

    @Test func isTruncated_monospacedIsAValidGate() {
        // The `.text` shortcut column measures in its own monospaced font; it must
        // still gate correctly at the extremes.
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
