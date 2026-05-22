import AppKit
import Carbon.HIToolbox

/// Process-singleton coordinating all global hotkey registrations: owns the
/// one shared Carbon `InstallEventHandler`, allocates `EventHotKeyID` ids, and
/// routes `kEventHotKeyPressed` to the matching `CarbonHotKey`.
///
/// While one of the app's NSMenus is tracking, Carbon hotkeys are paused and a
/// `RunLoopLocalEventMonitor` matches raw key events instead (menu mode).
@MainActor
final class CarbonHotKeyCenter {
    static let shared = CarbonHotKeyCenter()

    /// Identifies this app's hotkey events in the shared dispatcher. ASCII
    /// "SHKT" — distinct from other libraries' signatures.
    let signature: UInt32 = 0x5348_4B54

    private var hotKeys: [UInt32: CarbonHotKey] = [:]
    private var nextID: UInt32 = 1
    private var eventHandler: EventHandlerRef?

    private let hotKeyEventTypes = [
        EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        ),
    ]

    /// Hotkey delivery mode.
    enum Mode: Equatable {
        /// Carbon hotkeys registered and live.
        case normal
        /// One of the app's NSMenus is tracking — Carbon hotkeys are paused;
        /// the raw-key monitor matches combos instead.
        case menuOpen
    }

    private(set) var mode: Mode = .normal

    /// Count of NSMenus currently tracking. NSMenu posts begin/end per menu,
    /// so a submenu opening/closing nests — only depth 0 means no menu is open.
    private var menuTrackingDepth = 0

    private var menuObservers: [NSObjectProtocol] = []
    private lazy var menuKeyMonitor = RunLoopLocalEventMonitor(
        matching: [.keyDown],
        mode: .eventTracking
    ) { [weak self] event in
        guard let self else { return event }
        return handleRawKeyDown(event) ? nil : event
    }

    private init() {}

    /// Number of live registrations. Test/diagnostic accessor.
    var registeredCount: Int { hotKeys.count }

    /// Registers a global hotkey for `combo`. Returns the `CarbonHotKey`
    /// handle, or `nil` if `RegisterEventHotKey` failed (e.g. the combo is
    /// already registered by this process).
    func register(
        combo: CarbonHotKeyCombo,
        onKeyDown: @escaping () -> Void
    ) -> CarbonHotKey? {
        installMenuObserversIfNeeded()
        installEventHandlerIfNeeded()
        let id = nextID
        nextID += 1
        let hotKey = CarbonHotKey(id: id, combo: combo, onKeyDown: onKeyDown)
        if mode == .menuOpen {
            // A menu is tracking — stay paused; the raw-key monitor matches
            // this hotkey via the `hotKeys` table. resumeAllHotKeys() performs
            // the real Carbon registration when the menu closes.
            hotKeys[id] = hotKey
            return hotKey
        }
        guard let ref = carbonRegister(hotKey) else { return nil }
        hotKey.eventHotKeyRef = ref
        hotKeys[id] = hotKey
        return hotKey
    }

    /// Unregisters a single hotkey.
    func unregister(_ hotKey: CarbonHotKey) {
        if let ref = hotKey.eventHotKeyRef {
            UnregisterEventHotKey(ref)
            hotKey.eventHotKeyRef = nil
        }
        hotKeys.removeValue(forKey: hotKey.id)
    }

    /// Unregisters every hotkey. Used by `stop()` and tests.
    func unregisterAll() {
        for hotKey in hotKeys.values {
            if let ref = hotKey.eventHotKeyRef {
                UnregisterEventHotKey(ref)
                hotKey.eventHotKeyRef = nil
            }
        }
        hotKeys.removeAll()
    }

    // MARK: - Menu mode

    private func installMenuObserversIfNeeded() {
        guard menuObservers.isEmpty else { return }
        let center = NotificationCenter.default
        let begin = center.addObserver(
            forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.handleMenuTrackingChange(isOpen: true) }
        }
        let end = center.addObserver(
            forName: NSMenu.didEndTrackingNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.handleMenuTrackingChange(isOpen: false) }
        }
        menuObservers = [begin, end]
    }

    /// Adjusts the menu-tracking depth and updates `mode`. NSMenu posts
    /// begin/end notifications per menu; nested submenus increment/decrement
    /// the depth, so Carbon hotkeys stay paused until the *last* menu closes.
    /// Internal (not `private`) so tests can drive it without a live menu.
    func handleMenuTrackingChange(isOpen: Bool) {
        if isOpen {
            menuTrackingDepth += 1
        } else {
            menuTrackingDepth = max(0, menuTrackingDepth - 1)
        }
        let newMode: Mode = menuTrackingDepth > 0 ? .menuOpen : .normal
        guard newMode != mode else { return }
        mode = newMode
        switch newMode {
        case .menuOpen:
            pauseAllHotKeys()
            menuKeyMonitor.start()
        case .normal:
            menuKeyMonitor.stop()
            resumeAllHotKeys()
        }
    }

    private func pauseAllHotKeys() {
        for hotKey in hotKeys.values {
            if let ref = hotKey.eventHotKeyRef {
                UnregisterEventHotKey(ref)
                hotKey.eventHotKeyRef = nil
            }
        }
    }

    private func resumeAllHotKeys() {
        for hotKey in hotKeys.values where hotKey.eventHotKeyRef == nil {
            hotKey.eventHotKeyRef = carbonRegister(hotKey)
        }
    }

    /// Matches a raw `.keyDown` against the registered combos (menu mode).
    /// Returns `true` if a hotkey fired (so the event is consumed).
    private func handleRawKeyDown(_ event: NSEvent) -> Bool {
        let keyCode = UInt32(event.keyCode)
        let carbonMods = CarbonModifiers.carbon(from: event.modifierFlags)
        guard let hotKey = hotKeys.values.first(where: {
            $0.combo.keyCode == keyCode && $0.combo.carbonModifiers == carbonMods
        }) else { return false }
        hotKey.onKeyDown()
        return true
    }

    // MARK: - Carbon plumbing

    private func carbonRegister(_ hotKey: CarbonHotKey) -> EventHotKeyRef? {
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            hotKey.combo.keyCode,
            hotKey.combo.carbonModifiers,
            EventHotKeyID(signature: signature, id: hotKey.id),
            GetEventDispatcherTarget(),
            0,
            &ref
        )
        guard status == noErr, let ref else { return nil }
        return ref
    }

    private func installEventHandlerIfNeeded() {
        guard eventHandler == nil, let dispatcher = GetEventDispatcherTarget() else { return }
        var handler: EventHandlerRef?
        let status = InstallEventHandler(
            dispatcher,
            carbonHotKeyEventHandler,
            hotKeyEventTypes.count,
            hotKeyEventTypes,
            Unmanaged.passUnretained(self).toOpaque(),
            &handler
        )
        guard status == noErr else { return }
        eventHandler = handler
    }

    /// Called by the C trampoline (already on the main thread) for a
    /// `kEventHotKeyPressed` event.
    fileprivate func handleHotKeyEvent(_ event: EventRef) -> OSStatus {
        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            UInt32(kEventParamDirectObject),
            UInt32(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )
        guard status == noErr,
              hotKeyID.signature == signature,
              let hotKey = hotKeys[hotKeyID.id]
        else { return OSStatus(eventNotHandledErr) }
        hotKey.onKeyDown()
        return noErr
    }
}

/// C trampoline for the Carbon event handler. `kEventHotKeyPressed` is
/// delivered on the main thread; assert that and hop into the `@MainActor`
/// center via `assumeIsolated` — no `Task` dispatch.
private func carbonHotKeyEventHandler(
    _: EventHandlerCallRef?,
    event: EventRef?,
    userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event, let userData else { return OSStatus(eventNotHandledErr) }
    guard Thread.isMainThread else {
        assertionFailure("Carbon hotkey callback must run on the main thread")
        return OSStatus(eventNotHandledErr)
    }
    let center = Unmanaged<CarbonHotKeyCenter>.fromOpaque(userData).takeUnretainedValue()
    let address = UInt(bitPattern: event)
    return MainActor.assumeIsolated {
        guard let event = EventRef(bitPattern: address) else {
            return OSStatus(eventNotHandledErr)
        }
        return center.handleHotKeyEvent(event)
    }
}
