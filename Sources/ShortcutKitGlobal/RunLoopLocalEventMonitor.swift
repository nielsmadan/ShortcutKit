import AppKit

/// A local `NSEvent` monitor that only delivers events while the main run loop
/// is in a given mode. Used for the menu-mode raw-key fallback: the standard
/// local monitor is silent while an `NSMenu` tracks, because tracking runs the
/// run loop in `.eventTracking`.
///
/// The handler returns the event to let it through, or `nil` to consume it.
@MainActor
final class RunLoopLocalEventMonitor {
    private let mask: NSEvent.EventTypeMask
    private let mode: RunLoop.Mode
    private let handler: (NSEvent) -> NSEvent?
    private var observer: CFRunLoopObserver?

    init(
        matching mask: NSEvent.EventTypeMask,
        mode: RunLoop.Mode,
        handler: @escaping (NSEvent) -> NSEvent?
    ) {
        self.mask = mask
        self.mode = mode
        self.handler = handler
    }

    func start() {
        guard observer == nil else { return }
        // beforeWaiting fires once per run-loop pass while in `mode`; drain the
        // app's event queue for matching events and route them to `handler`.
        let observer = CFRunLoopObserverCreateWithHandler(
            kCFAllocatorDefault,
            CFRunLoopActivity.beforeWaiting.rawValue,
            true,
            0
        ) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.drain() }
        }
        CFRunLoopAddObserver(
            CFRunLoopGetMain(),
            observer,
            CFRunLoopMode(mode.rawValue as CFString)
        )
        self.observer = observer
    }

    func stop() {
        guard let observer else { return }
        CFRunLoopRemoveObserver(
            CFRunLoopGetMain(),
            observer,
            CFRunLoopMode(mode.rawValue as CFString)
        )
        self.observer = nil
    }

    private func drain() {
        while let event = NSApp.nextEvent(
            matching: mask,
            until: nil, // non-blocking poll
            inMode: mode,
            dequeue: true
        ) {
            if let passthrough = handler(event) {
                NSApp.postEvent(passthrough, atStart: false)
            }
        }
    }
}
