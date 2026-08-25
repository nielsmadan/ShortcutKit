import AppKit
import Combine
import ShortcutKit

@MainActor
protocol ShortcutHintHost: AnyObject {
    var options: HintHUDOptions { get }
    var isEligible: Bool { get }
    var window: NSWindow? { get }
    var anchorArea: CGFloat { get }

    func present(_ context: HintToastContext, id: UUID) -> Bool
    func dismiss(id: UUID)
}

@MainActor
struct HintHUDApplicationWindows {
    let keyWindow: NSWindow?
    let orderedWindows: [NSWindow]
    let mainWindow: NSWindow?
}

/// Coordinates one shortcut hint stream across roots that share this presenter.
@MainActor
public final class ShortcutHintPresenter {
    private struct HostRegistration {
        let id: UUID
        weak var host: (any ShortcutHintHost)?
    }

    private struct CurrentPresentation {
        let id: UUID
        let hostID: UUID
    }

    private let registry: ShortcutRegistry
    private let isApplicationActive: @MainActor @Sendable () -> Bool
    private let applicationWindows: @MainActor @Sendable () -> HintHUDApplicationWindows
    private let announce: @MainActor @Sendable (String) -> Void
    private let sleep: @MainActor @Sendable (Duration) async -> Void
    private var gate = HintPolicyGate()
    private var hosts: [HostRegistration] = []
    private var current: CurrentPresentation?
    private var dismissTask: Task<Void, Never>?
    private var actionCancellable: AnyCancellable?

    /// Creates a presenter that observes programmatic actions from `registry`.
    public convenience init(registry: ShortcutRegistry) {
        self.init(
            registry: registry,
            isApplicationActive: { NSApplication.shared.isActive },
            applicationWindows: {
                HintHUDApplicationWindows(
                    keyWindow: NSApplication.shared.keyWindow,
                    orderedWindows: NSApplication.shared.orderedWindows,
                    mainWindow: NSApplication.shared.mainWindow
                )
            },
            announce: Self.postAccessibilityAnnouncement,
            sleep: { duration in try? await Task.sleep(for: duration) }
        )
    }

    init(
        registry: ShortcutRegistry,
        isApplicationActive: @escaping @MainActor @Sendable () -> Bool,
        applicationWindows: @escaping @MainActor @Sendable () -> HintHUDApplicationWindows = {
            HintHUDApplicationWindows(keyWindow: nil, orderedWindows: [], mainWindow: nil)
        },
        announce: @escaping @MainActor @Sendable (String) -> Void,
        sleep: @escaping @MainActor @Sendable (Duration) async -> Void
    ) {
        self.registry = registry
        self.isApplicationActive = isApplicationActive
        self.applicationWindows = applicationWindows
        self.announce = announce
        self.sleep = sleep
        actionCancellable = registry.actionFired.sink { @MainActor [weak self] event in
            self?.receive(event)
        }
    }

    @discardableResult
    func register(_ host: any ShortcutHintHost) -> UUID {
        removeReleasedHosts()
        let id = UUID()
        hosts.append(HostRegistration(id: id, host: host))
        return id
    }

    func unregister(_ id: UUID) {
        if current?.hostID == id {
            dismissCurrent()
        }
        hosts.removeAll { $0.id == id || $0.host == nil }
    }

    func hostDidBecomeIneligible(_ id: UUID?) {
        guard let id, current?.hostID == id else { return }
        dismissCurrent()
    }

    func receive(_ event: ActionFiredEvent) {
        guard isApplicationActive(), registry.hintsEnabled, event.source == .programmatic else { return }
        guard let (hostID, host) = selectedHost() else { return }
        guard let context = context(for: event) else { return }
        let action = ActionRef(contextID: event.contextID, actionID: event.actionID)
        guard gate.shouldShow(action: action, policy: registry.hintFrequency) else { return }

        let presentationID = UUID()
        guard host.present(context, id: presentationID) else { return }

        dismissCurrent()
        current = CurrentPresentation(id: presentationID, hostID: hostID)
        gate.markShown(action: action)
        announce(context.text)
        scheduleDismissal(of: presentationID, after: host.options.duration)
    }

    private func selectedHost() -> (UUID, any ShortcutHintHost)? {
        removeReleasedHosts()
        let windows = applicationWindows()
        if let keyWindow = windows.keyWindow,
           let selected = preferredHost(matching: keyWindow)
        {
            return selected
        }
        for window in windows.orderedWindows {
            if let selected = preferredHost(matching: window) {
                return selected
            }
        }
        if let mainWindow = windows.mainWindow,
           let selected = preferredHost(matching: mainWindow)
        {
            return selected
        }
        for registration in hosts.reversed() {
            if let host = registration.host, host.isEligible {
                return (registration.id, host)
            }
        }
        return nil
    }

    private func preferredHost(matching window: NSWindow) -> (UUID, any ShortcutHintHost)? {
        var selected: (registration: HostRegistration, host: any ShortcutHintHost)?
        for registration in hosts {
            guard let host = registration.host,
                  host.isEligible,
                  let hostWindow = host.window,
                  windowIsDescendant(window, of: hostWindow)
            else { continue }
            if selected == nil || host.anchorArea > (selected?.host.anchorArea ?? 0) {
                selected = (registration, host)
            }
        }
        guard let selected else { return nil }
        return (selected.registration.id, selected.host)
    }

    private func context(for event: ActionFiredEvent) -> HintToastContext? {
        guard let group = registry.keyBindings.groups.first(where: { $0.contextID == event.contextID }),
              let entry = group.entries.first(where: { $0.actionID == event.actionID }),
              let binding = entry.effectiveShortcuts.first
        else { return nil }

        let name = String(localized: entry.displayName)
        let shortcut = binding.displayString
        return HintToastContext(
            actionName: name,
            shortcut: shortcut,
            text: uiString("Tip: \(name) is bound to \(shortcut)")
        )
    }

    private func scheduleDismissal(of id: UUID, after duration: Duration) {
        dismissTask?.cancel()
        dismissTask = Task { @MainActor [weak self, sleep] in
            await sleep(duration)
            guard !Task.isCancelled else { return }
            self?.dismiss(id: id)
        }
    }

    private func dismiss(id: UUID) {
        guard current?.id == id else { return }
        dismissCurrent()
    }

    private func dismissCurrent() {
        dismissTask?.cancel()
        dismissTask = nil
        guard let current else { return }
        hosts.first(where: { $0.id == current.hostID })?.host?.dismiss(id: current.id)
        self.current = nil
    }

    private func removeReleasedHosts() {
        hosts.removeAll { $0.host == nil }
    }

    private static func postAccessibilityAnnouncement(_ text: String) {
        NSAccessibility.post(
            element: NSApplication.shared,
            notification: .announcementRequested,
            userInfo: [
                .announcement: text,
                .priority: NSAccessibilityPriorityLevel.low.rawValue,
            ]
        )
    }
}

@MainActor
private func windowIsDescendant(_ window: NSWindow, of ancestor: NSWindow) -> Bool {
    var candidate: NSWindow? = window
    while let current = candidate {
        if current === ancestor { return true }
        candidate = current.sheetParent ?? current.parent
    }
    return false
}
