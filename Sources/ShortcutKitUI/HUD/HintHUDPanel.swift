import AppKit

@MainActor
final class HintHUDPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        hidesOnDeactivate = true
        animationBehavior = .none
        collectionBehavior = [.transient, .fullScreenAuxiliary, .ignoresCycle]
        isReleasedWhenClosed = false
    }
}
