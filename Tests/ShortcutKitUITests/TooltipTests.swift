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
        #expect(legendTextIsTruncated(" ", fontSize: 10, width: 500) == false)
    }

    @Test func isTruncated_longStringOverflows() {
        // A 200-char string at 12pt easily exceeds a 50pt frame.
        let long = String(repeating: "abc ", count: 50)
        #expect(legendTextIsTruncated(long, fontSize: 12, width: 50) == true)
    }

    @Test func isTruncated_emptyStringNeverTruncates() {
        #expect(legendTextIsTruncated("", fontSize: 12, width: 100) == false)
        #expect(legendTextIsTruncated("", fontSize: 12, width: 0) == false)
    }

    @Test func isTruncated_zeroWidthReturnsFalse() {
        // Guard: no meaningful "does it fit" answer for a zero-width frame —
        // treat as not-truncated so we don't fire tooltips during initial layout
        // before `frameWidth` is measured.
        #expect(legendTextIsTruncated("anything", fontSize: 12, width: 0) == false)
    }

    @Test func isTruncated_transitionsAtOwnWidth() {
        // Derive the string's own rendered width via the same measurement path,
        // then bracket the strict `>` gate: it fits at exactly its own width and
        // truncates just below. OS-version-independent (expected width is measured,
        // not pinned), and unlike the old test it exercises the fit→truncate flip.
        let text = "Toggle Diagnostics Overlay"
        let w = (text as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 12)]).width
        #expect(legendTextIsTruncated(text, fontSize: 12, width: w) == false)
        #expect(legendTextIsTruncated(text, fontSize: 12, width: w - 1) == true)
    }

    @Test func isTruncated_monospacedIsAValidGate() {
        // The `.text` shortcut column measures monospaced; it must still gate
        // correctly at the extremes.
        #expect(legendTextIsTruncated("Command K", fontSize: 12, width: 1, monospaced: true) == true)
        #expect(legendTextIsTruncated("Command K", fontSize: 12, width: 500, monospaced: true) == false)
    }
}
