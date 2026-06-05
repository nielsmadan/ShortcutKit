import AppKit
import Combine
import ShortcutField

/// Carbon `RegisterEventHotKey`-backed `GlobalActivator`. Walks a
/// `ShortcutRegistry` for `.global`-scoped contexts, registers each effective
/// binding as a system-wide hotkey, and reports per-binding outcomes through
/// `status`.
///
/// Typically one per registry. Raw Carbon registration is delegated to the
/// process-singleton `CarbonHotKeyCenter`.
@MainActor
public final class CarbonGlobalActivator: GlobalActivator {
    public private(set) var status: [BindingID: GlobalBindingStatus] = [:]

    private let center = CarbonHotKeyCenter.shared
    private var registry: ShortcutRegistry?
    /// Live registrations keyed by BindingID, so auto-sync (Task 12) can diff.
    private var registered: [BindingID: CarbonHotKey] = [:]
    private var isStarted = false
    /// Observes `didBecomeActive` to re-verify against an updated system set.
    private var activeObserver: NSObjectProtocol?
    /// Observes `didEndTracking` to re-verify after a menu closes, catching
    /// hotkeys that failed to re-register in `resumeAllHotKeys()`.
    private var menuEndObserver: NSObjectProtocol?
    /// Snapshot of the shortcut currently registered for each BindingID —
    /// the diff baseline.
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

    /// Re-reads global bindings and applies the delta against the live set.
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
                registry?.fireGlobalAction(contextID: id.contextID, actionID: id.actionID)
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

    /// Pure system-shadowing check. A `.registered` binding whose combo is in
    /// the system-shortcut set is downgraded to `.shadowedBySystem`; any other
    /// status is returned unchanged.
    static func verifiedStatus(
        current: GlobalBindingStatus,
        combo: CarbonHotKeyCombo,
        systemCombos: Set<CarbonHotKeyCombo>
    ) -> GlobalBindingStatus {
        guard current == .registered, systemCombos.contains(combo) else { return current }
        return .shadowedBySystem
    }

    /// Snapshot of the live system-shortcut set as Carbon combos.
    private func systemCombos() -> Set<CarbonHotKeyCombo> {
        Set(CarbonSystemShortcuts().currentSystemShortcuts().map {
            CarbonHotKeyCombo(
                keyCode: UInt32($0.keyCode),
                carbonModifiers: CarbonModifiers.carbon(from: $0.modifiers)
            )
        })
    }

    /// Cross-checks every registered combo against the live system set,
    /// downgrading any system-claimed binding to `.shadowedBySystem`, and
    /// surfaces hotkeys that failed to re-register after a menu closed.
    private func verifyRegistrations() {
        let system = systemCombos()
        let menuTracking = (center.mode == .menuOpen)
        for (id, hotKey) in registered {
            guard let current = status[id] else { continue }
            // A registered hotkey with no live Carbon ref while NOT in menu
            // mode means a re-registration failed (e.g. resumeAllHotKeys could
            // not reclaim the combo after the menu closed). Surface it.
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
