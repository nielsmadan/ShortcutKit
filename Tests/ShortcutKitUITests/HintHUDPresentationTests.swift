import CoreGraphics
@testable import ShortcutKitUI
import Testing

@MainActor
struct HintHUDPresentationTests {
    @Test func screenContainingPointerWinsOverFallback() {
        let left = CGRect(x: -1920, y: 0, width: 1920, height: 1080)
        let right = CGRect(x: 0, y: 0, width: 2560, height: 1440)
        let leftVisible = CGRect(x: -1920, y: 0, width: 1920, height: 1055)

        let selected = hintScreenFrame(
            containing: CGPoint(x: -400, y: 500),
            candidates: [
                HintHUDScreenFrame(frame: right, visibleFrame: right),
                HintHUDScreenFrame(frame: left, visibleFrame: leftVisible),
            ],
            fallback: right
        )

        #expect(selected == leftVisible)
    }

    @Test func screenFallbackIsUsedWhenPointerIsOutsideEveryFrame() {
        let fallback = CGRect(x: 0, y: 0, width: 1440, height: 900)

        let selected = hintScreenFrame(
            containing: CGPoint(x: 2000, y: 2000),
            candidates: [HintHUDScreenFrame(frame: fallback, visibleFrame: fallback)],
            fallback: fallback
        )

        #expect(selected == fallback)
    }

    @Test func screenPointConvertsToTopLeadingPanelCoordinates() {
        let frame = CGRect(x: -1920, y: -200, width: 1920, height: 1080)

        let point = hintPanelPoint(
            fromScreenPoint: CGPoint(x: -1800, y: 700),
            referenceFrame: frame
        )

        #expect(point == CGPoint(x: 120, y: 180))
    }
}
