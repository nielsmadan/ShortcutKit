import AppKit

/// Delivers local events while the main run loop is in a specified mode.
///
/// This supports menu tracking, where standard local event monitors are silent.
/// The handler returns an event to pass it through or `nil` to consume it.
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
            until: nil,
            inMode: mode,
            dequeue: true
        ) {
            if let passthrough = handler(event) {
                NSApp.postEvent(passthrough, atStart: false)
            }
        }
    }
}
