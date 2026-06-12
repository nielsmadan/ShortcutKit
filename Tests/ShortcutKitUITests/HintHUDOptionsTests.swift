import CoreGraphics
@testable import ShortcutKitUI
import SwiftUI
import Testing

@MainActor
struct HintHUDOptionsTests {
    @Test func defaultOptionsAreTopTrailingTwoSeconds() {
        let options = HintHUDOptions.default
        #expect(options.placement == .topTrailing)
        #expect(options.duration == .seconds(2))
    }

    @Test func fixedPlacementsMapToMatchingAlignment() {
        #expect(HintHUDPlacement.topLeading.alignment == .topLeading)
        #expect(HintHUDPlacement.top.alignment == .top)
        #expect(HintHUDPlacement.topTrailing.alignment == .topTrailing)
        #expect(HintHUDPlacement.leading.alignment == .leading)
        #expect(HintHUDPlacement.center.alignment == .center)
        #expect(HintHUDPlacement.trailing.alignment == .trailing)
        #expect(HintHUDPlacement.bottomLeading.alignment == .bottomLeading)
        #expect(HintHUDPlacement.bottom.alignment == .bottom)
        #expect(HintHUDPlacement.bottomTrailing.alignment == .bottomTrailing)
    }

    @Test func cursorFallsBackToTopAlignment() {
        #expect(HintHUDPlacement.cursor.alignment == .top)
    }

    // MARK: - clampedToastCenter

    private let container = CGSize(width: 400, height: 300)
    private let toast = CGSize(width: 80, height: 20)

    @Test func cursorWellInsideOffsetsDownRight() {
        let center = clampedToastCenter(cursor: CGPoint(x: 100, y: 100), container: container, toast: toast)
        // top-leading = cursor + gap(12); centre = that + half-size (40 / 10).
        #expect(center.x == 152)
        #expect(center.y == 122)
    }

    @Test func cursorNearRightEdgeClampsX() {
        let center = clampedToastCenter(cursor: CGPoint(x: 390, y: 100), container: container, toast: toast)
        // maxX = 400 - 40 - 8 = 352.
        #expect(center.x == 352)
    }

    @Test func cursorNearBottomEdgeClampsY() {
        let center = clampedToastCenter(cursor: CGPoint(x: 100, y: 295), container: container, toast: toast)
        // maxY = 300 - 10 - 8 = 282.
        #expect(center.y == 282)
    }

    @Test func containerTooSmallFallsBackToCentre() {
        let tiny = CGSize(width: 30, height: 30)
        let center = clampedToastCenter(cursor: CGPoint(x: 5, y: 5), container: tiny, toast: toast)
        #expect(center.x == 15)
        #expect(center.y == 15)
    }
}
