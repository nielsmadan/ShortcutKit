import CoreGraphics

struct HintHUDScreenFrame {
    let frame: CGRect
    let visibleFrame: CGRect
}

func hintScreenFrame(
    containing point: CGPoint,
    candidates: [HintHUDScreenFrame],
    fallback: CGRect?
) -> CGRect? {
    candidates.first(where: { $0.frame.contains(point) })?.visibleFrame ?? fallback
}

func hintPanelPoint(fromScreenPoint point: CGPoint, referenceFrame: CGRect) -> CGPoint {
    CGPoint(
        x: point.x - referenceFrame.minX,
        y: referenceFrame.maxY - point.y
    )
}
