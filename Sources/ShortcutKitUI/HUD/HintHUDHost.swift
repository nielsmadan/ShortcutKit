import AppKit
import Combine
import SwiftUI

@MainActor
struct HintHUDEnvironment {
    let colorScheme: ColorScheme
    let locale: Locale
    let layoutDirection: LayoutDirection
    let font: Font?
    let controlSize: ControlSize
    let dynamicTypeSize: DynamicTypeSize
    let reduceMotion: Bool
    let hintStyle: AnyShortcutHintStyle

    static let `default` = HintHUDEnvironment(
        colorScheme: .light,
        locale: .current,
        layoutDirection: .leftToRight,
        font: nil,
        controlSize: .regular,
        dynamicTypeSize: .medium,
        reduceMotion: false,
        hintStyle: AnyShortcutHintStyle(ShortcutHintToastStyle())
    )
}

@MainActor
final class HintHUDHost: ObservableObject, ShortcutHintHost {
    struct Presentation {
        let id: UUID
        let context: HintToastContext
        let cursorPoint: CGPoint?
        let options: HintHUDOptions
        let environment: HintHUDEnvironment
    }

    @Published private(set) var current: Presentation?
    var options: HintHUDOptions
    var isVisible = false
    var cursorPoint: CGPoint?
    private(set) weak var anchorView: NSView?

    private var environment: HintHUDEnvironment
    private var renderer: @MainActor (HintToastContext) -> AnyView
    private let isApplicationActive: @MainActor @Sendable () -> Bool
    private weak var presenter: ShortcutHintPresenter?
    private var registrationID: UUID?
    private var panel: HintHUDPanel?
    private var panelDismissTask: Task<Void, Never>?
    private var panelCancellables: Set<AnyCancellable> = []

    var isEligible: Bool {
        guard isVisible else { return false }
        switch options.presentation {
        case .view:
            return anchorView == nil || window?.isVisible == true
        case .window, .screen:
            return window?.isVisible == true
        }
    }

    var window: NSWindow? { anchorView?.window }
    var presentationPanel: HintHUDPanel? { panel }

    var anchorArea: CGFloat {
        guard let anchorView else { return 0 }
        return anchorView.visibleRect.width * anchorView.visibleRect.height
    }

    init(
        options: HintHUDOptions,
        environment: HintHUDEnvironment = .default,
        isApplicationActive: @escaping @MainActor @Sendable () -> Bool = { NSApplication.shared.isActive },
        renderer: @escaping @MainActor (HintToastContext) -> AnyView = { context in
            AnyView(StyledShortcutHint(configuration: context))
        }
    ) {
        self.options = options
        self.environment = environment
        self.isApplicationActive = isApplicationActive
        self.renderer = renderer
    }

    func update(
        presenter: ShortcutHintPresenter,
        options: HintHUDOptions,
        environment: HintHUDEnvironment,
        renderer: @escaping @MainActor (HintToastContext) -> AnyView,
        anchorView: NSView
    ) {
        let presentationChanged = self.options.presentation != options.presentation
        self.options = options
        self.environment = environment
        self.renderer = renderer
        self.anchorView = anchorView
        isVisible = true
        connect(to: presenter)
        if presentationChanged, current != nil {
            presenter.hostDidBecomeIneligible(registrationID)
            hidePanel()
            return
        }
        refreshPanel()
    }

    func detach(anchorView: NSView) {
        guard self.anchorView === anchorView else { return }
        isVisible = false
        presenter?.hostDidBecomeIneligible(registrationID)
        disconnect()
        hidePanel()
        self.anchorView = nil
    }

    func anchorDidChange(_ anchorView: NSView) {
        guard self.anchorView === anchorView else { return }
        if anchorView.window == nil {
            presenter?.hostDidBecomeIneligible(registrationID)
        }
        refreshPanel()
    }

    func connect(to presenter: ShortcutHintPresenter) {
        guard self.presenter !== presenter else { return }
        disconnect()
        self.presenter = presenter
        registrationID = presenter.register(self)
    }

    func disconnect() {
        if let registrationID {
            presenter?.unregister(registrationID)
        }
        presenter = nil
        registrationID = nil
    }

    func present(_ context: HintToastContext, id: UUID) -> Bool {
        guard isEligible else { return false }
        let presentation = Presentation(
            id: id,
            context: context,
            cursorPoint: resolvedCursorPoint(),
            options: options,
            environment: environment
        )

        switch options.presentation {
        case .view:
            hidePanel()
            setCurrent(presentation)
        case .window, .screen:
            guard preparePanel() else { return false }
            setCurrent(presentation)
        }
        return true
    }

    func dismiss(id: UUID) {
        guard let presentation = current, presentation.id == id else { return }
        withAnimation(presentation.options.transition.animation(.easeIn(duration: 0.3))) {
            current = nil
        }
        if presentation.options.presentation != .view {
            schedulePanelHide(transition: presentation.options.transition)
        }
    }

    func render(_ context: HintToastContext) -> AnyView {
        renderer(context)
    }

    private func setCurrent(_ presentation: Presentation) {
        panelDismissTask?.cancel()
        panelDismissTask = nil
        withAnimation(presentation.options.transition.animation(.easeOut(duration: 0.2))) {
            current = presentation
        }
    }

    private func preparePanel() -> Bool {
        guard let frame = panelReferenceFrame(), let parent = presentationParent() else { return false }
        let panel = panel ?? makePanel()
        if panel.parent !== parent {
            panel.parent?.removeChildWindow(panel)
            parent.addChildWindow(panel, ordered: .above)
        }
        panel.level = parent.level
        panel.setFrame(frame, display: true)
        panel.orderFront(nil)
        installPanelObservers()
        return true
    }

    private func makePanel() -> HintHUDPanel {
        let panel = HintHUDPanel()
        panel.contentView = NSHostingView(rootView: HintHUDPanelRoot(host: self))
        self.panel = panel
        return panel
    }

    private func panelReferenceFrame() -> CGRect? {
        guard let window else { return nil }
        switch options.presentation {
        case .view:
            return nil
        case .window:
            return window.convertToScreen(window.contentLayoutRect)
        case .screen:
            let screens = NSScreen.screens
            if options.placement == .cursor {
                let pointer = NSEvent.mouseLocation
                let fallback = window.screen?.visibleFrame
                    ?? NSScreen.main?.visibleFrame
                    ?? screens.first?.visibleFrame
                return hintScreenFrame(
                    containing: pointer,
                    candidates: screens.map { HintHUDScreenFrame(frame: $0.frame, visibleFrame: $0.visibleFrame) },
                    fallback: fallback
                )
            }
            return window.screen?.visibleFrame
                ?? NSScreen.main?.visibleFrame
                ?? screens.first?.visibleFrame
        }
    }

    private func resolvedCursorPoint() -> CGPoint? {
        guard options.placement == .cursor else { return nil }
        switch options.presentation {
        case .view:
            return cursorPoint
        case .window, .screen:
            guard let frame = panelReferenceFrame() else { return nil }
            return hintPanelPoint(fromScreenPoint: NSEvent.mouseLocation, referenceFrame: frame)
        }
    }

    private func presentationParent() -> NSWindow? {
        guard var parent = window else { return nil }
        if let modalWindow = NSApplication.shared.modalWindow, modalWindow.isVisible {
            parent = modalWindow
        }
        while let sheet = parent.attachedSheet {
            parent = sheet
        }
        return parent
    }

    private func refreshPanel() {
        guard let current, current.options.presentation != .view else { return }
        if !isApplicationActive() {
            presenter?.hostDidBecomeIneligible(registrationID)
            return
        }
        _ = preparePanel()
    }

    private func installPanelObservers() {
        guard panelCancellables.isEmpty else { return }
        let center = NotificationCenter.default
        let names: [Notification.Name] = [
            NSWindow.didBecomeKeyNotification,
            NSWindow.willBeginSheetNotification,
            NSWindow.didEndSheetNotification,
            NSWindow.didMoveNotification,
            NSWindow.didResizeNotification,
            NSWindow.didChangeScreenNotification,
            NSApplication.didChangeScreenParametersNotification,
            NSApplication.didResignActiveNotification,
        ]
        for name in names {
            center.publisher(for: name)
                .sink { @MainActor [weak self] _ in self?.refreshPanel() }
                .store(in: &panelCancellables)
        }
    }

    private func schedulePanelHide(transition: HintHUDTransition) {
        panelDismissTask?.cancel()
        let delay: Duration = transition == .none ? .zero : .milliseconds(300)
        panelDismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, self?.current == nil else { return }
            self?.hidePanel()
        }
    }

    private func hidePanel() {
        panelDismissTask?.cancel()
        panelDismissTask = nil
        panelCancellables.removeAll()
        guard let panel else { return }
        panel.parent?.removeChildWindow(panel)
        panel.orderOut(nil)
        panel.contentView = nil
        self.panel = nil
    }
}

@MainActor
private struct HintHUDPanelRoot: View {
    @ObservedObject var host: HintHUDHost

    var body: some View {
        Group {
            if let presentation = host.current, presentation.options.presentation != .view {
                HintHUDToastOverlay(presentation: presentation) { context in
                    host.render(context)
                }
                .environment(\.colorScheme, presentation.environment.colorScheme)
                .environment(\.locale, presentation.environment.locale)
                .environment(\.layoutDirection, presentation.environment.layoutDirection)
                .environment(\.font, presentation.environment.font)
                .environment(\.controlSize, presentation.environment.controlSize)
                .environment(\.dynamicTypeSize, presentation.environment.dynamicTypeSize)
                .environment(\.shortcutHintStyle, presentation.environment.hintStyle)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clear)
        .allowsHitTesting(false)
    }
}

@MainActor
final class HintHUDAnchorView: NSView {
    weak var host: HintHUDHost?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        host?.anchorDidChange(self)
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        host?.anchorDidChange(self)
    }
}

@MainActor
struct HintHUDAnchorReader: NSViewRepresentable {
    let host: HintHUDHost
    let presenter: ShortcutHintPresenter
    let options: HintHUDOptions
    let environment: HintHUDEnvironment
    let renderer: @MainActor (HintToastContext) -> AnyView

    func makeNSView(context _: Context) -> HintHUDAnchorView {
        let view = HintHUDAnchorView()
        view.host = host
        return view
    }

    func updateNSView(_ view: HintHUDAnchorView, context _: Context) {
        view.host = host
        host.update(
            presenter: presenter,
            options: options,
            environment: environment,
            renderer: renderer,
            anchorView: view
        )
    }

    static func dismantleNSView(_ view: HintHUDAnchorView, coordinator _: ()) {
        view.host?.detach(anchorView: view)
        view.host = nil
    }
}
