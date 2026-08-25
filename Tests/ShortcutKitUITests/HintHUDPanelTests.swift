import AppKit
import ShortcutKit
@testable import ShortcutKitUI
import SwiftUI
import Testing

@MainActor
struct HintHUDPanelTests {
    @Test func panelIsNonactivatingAndClickThrough() {
        let panel = HintHUDPanel()

        #expect(panel.canBecomeKey == false)
        #expect(panel.canBecomeMain == false)
        #expect(panel.styleMask.contains(.nonactivatingPanel))
        #expect(panel.ignoresMouseEvents)
        #expect(panel.hidesOnDeactivate)
        #expect(panel.isOpaque == false)
    }

    @Test func panelFollowsHostSpaceWithoutJoiningEverySpace() {
        let panel = HintHUDPanel()

        #expect(panel.collectionBehavior.contains(.transient))
        #expect(panel.collectionBehavior.contains(.fullScreenAuxiliary))
        #expect(panel.collectionBehavior.contains(.ignoresCycle))
        #expect(panel.collectionBehavior.contains(.canJoinAllSpaces) == false)
    }

    @Test func hostReparentsPanelAboveSheetAndReleasesItOnDetach() async {
        let registry = ShortcutRegistry(contexts: [])
        let presenter = ShortcutHintPresenter(
            registry: registry,
            isApplicationActive: { true },
            announce: { _ in },
            sleep: { _ in }
        )
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 600, height: 400),
            styleMask: [],
            backing: .buffered,
            defer: false
        )
        let anchor = HintHUDAnchorView(frame: window.contentView?.bounds ?? .zero)
        window.contentView = anchor
        window.orderFront(nil)
        let host = HintHUDHost(
            options: HintHUDOptions(presentation: .window, transition: .none),
            isApplicationActive: { true }
        )
        host.update(
            presenter: presenter,
            options: HintHUDOptions(presentation: .window, transition: .none),
            environment: .default,
            renderer: { _ in AnyView(EmptyView()) },
            anchorView: anchor
        )

        let id = UUID()
        #expect(host.present(HintToastContext(actionName: "Rename", shortcut: "⌘r", text: "Tip"), id: id))
        #expect(host.presentationPanel?.parent === window)

        let sheet = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 300, height: 200),
            styleMask: [],
            backing: .buffered,
            defer: false
        )
        window.beginSheet(sheet) { _ in }
        await Task.yield()
        #expect(window.attachedSheet === sheet)
        NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: sheet)
        #expect(host.presentationPanel?.parent === sheet)

        host.detach(anchorView: anchor)
        #expect(host.presentationPanel == nil)
        window.endSheet(sheet)
        window.orderOut(nil)
    }
}
