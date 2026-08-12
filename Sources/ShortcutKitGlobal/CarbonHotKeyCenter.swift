import AppKit
import Carbon.HIToolbox

/// Coordinates the process's Carbon hotkey registrations and event handler.
///
/// While one of the app's NSMenus is tracking, Carbon hotkeys are paused and a
/// `RunLoopLocalEventMonitor` matches raw key events instead (menu mode).
@MainActor
final class CarbonHotKeyCenter {
    static let shared = CarbonHotKeyCenter()

    /// ASCII `SHKT`, identifying this library's events in Carbon's dispatcher.
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

    enum Mode: Equatable {
        case normal
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

    var registeredCount: Int { hotKeys.count }

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
            hotKeys[id] = hotKey
            return hotKey
        }
        guard let ref = carbonRegister(hotKey) else { return nil }
        hotKey.eventHotKeyRef = ref
        hotKeys[id] = hotKey
        return hotKey
    }

    func unregister(_ hotKey: CarbonHotKey) {
        if let ref = hotKey.eventHotKeyRef {
            UnregisterEventHotKey(ref)
            hotKey.eventHotKeyRef = nil
        }
        hotKeys.removeValue(forKey: hotKey.id)
    }

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

/// Bridges Carbon's main-thread callback into the actor-isolated center.
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
