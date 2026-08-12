import AppKit
import Combine
import ShortcutField

/// A Carbon-backed activator for global shortcut contexts.
///
/// Registration outcomes are reported per binding through `status`.
@MainActor
public final class CarbonGlobalActivator: GlobalActivator {
    public private(set) var status: [BindingID: GlobalBindingStatus] = [:]

    private let center = CarbonHotKeyCenter.shared
    private var registry: ShortcutRegistry?
    private var registered: [BindingID: CarbonHotKey] = [:]
    private var isStarted = false
    private var activeObserver: NSObjectProtocol?
    private var menuEndObserver: NSObjectProtocol?
    private var currentShortcuts: [BindingID: Shortcut] = [:]
    private var bindingsSubscription: AnyCancellable?

    public init() {}

    public func start(_ registry: ShortcutRegistry) throws {
        guard !isStarted else { throw GlobalActivatorError.alreadyStarted }
        isStarted = true
        self.registry = registry
        syncRegistrations()
        activeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.verifyRegistrations() }
        }
        menuEndObserver = NotificationCenter.default.addObserver(
            forName: NSMenu.didEndTrackingNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.verifyRegistrations() }
        }
        bindingsSubscription = registry.$keyBindings
            .dropFirst()
            .sink { [weak self] _ in
                MainActor.assumeIsolated { self?.syncRegistrations() }
            }
    }

    public func stop() {
        for hotKey in registered.values {
            center.unregister(hotKey)
        }
        if let activeObserver {
            NotificationCenter.default.removeObserver(activeObserver)
        }
        activeObserver = nil
        if let menuEndObserver {
            NotificationCenter.default.removeObserver(menuEndObserver)
        }
        menuEndObserver = nil
        bindingsSubscription?.cancel()
        bindingsSubscription = nil
        registered.removeAll()
        currentShortcuts.removeAll()
        status.removeAll()
        registry = nil
        isStarted = false
    }

    // MARK: - Registration

    private func syncRegistrations() {
        guard let registry else { return }
        var newShortcuts: [BindingID: Shortcut] = [:]
        for binding in registry.globalBindings() {
            newShortcuts[binding.id] = binding.shortcut
        }
        let diff = GlobalBindingDiff.compute(old: currentShortcuts, new: newShortcuts)

        for id in diff.toRemove {
            if let hotKey = registered.removeValue(forKey: id) {
                center.unregister(hotKey)
            }
            status[id] = nil
        }
        for (id, shortcut) in diff.toAdd {
            guard let combo = ShortcutCarbonBridge.combo(for: shortcut) else {
                status[id] = .unsupportedTrigger
                continue
            }
            guard let hotKey = center.register(combo: combo, onKeyDown: { [weak registry] in
                registry?.dispatchGlobalAction(id.ref)
            }) else {
                status[id] = .failed(reason: .registrationRejected)
                continue
            }
            registered[id] = hotKey
            status[id] = .registered
        }
        currentShortcuts = newShortcuts
        verifyRegistrations()
    }

    // MARK: - System-shadowing verification

    static func verifiedStatus(
        current: GlobalBindingStatus,
        combo: CarbonHotKeyCombo,
        systemCombos: Set<CarbonHotKeyCombo>
    ) -> GlobalBindingStatus {
        guard current == .registered, systemCombos.contains(combo) else { return current }
        return .shadowedBySystem
    }

    private func systemCombos() -> Set<CarbonHotKeyCombo> {
        Set(CarbonSystemShortcuts().currentSystemShortcuts().map {
            CarbonHotKeyCombo(
                keyCode: UInt32($0.keyCode),
                carbonModifiers: CarbonModifiers.carbon(from: $0.modifiers)
            )
        })
    }

    private func verifyRegistrations() {
        let system = systemCombos()
        let menuTracking = (center.mode == .menuOpen)
        for (id, hotKey) in registered {
            guard let current = status[id] else { continue }
            // A nil Carbon handle outside menu mode means re-registration failed.
            if !menuTracking, hotKey.eventHotKeyRef == nil, current == .registered {
                status[id] = .failed(reason: .reregistrationFailed)
                continue
            }
            status[id] = Self.verifiedStatus(
                current: current, combo: hotKey.combo, systemCombos: system
            )
        }
    }
}
