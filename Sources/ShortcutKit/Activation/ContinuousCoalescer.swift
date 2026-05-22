import CoreFoundation
import Foundation

/// Coalesces continuous-shortcut fires into one dispatch per (context, action)
/// per run-loop pass. Backed by a `CFRunLoopObserver` on `.beforeWaiting`
/// in `.commonModes`. Frame-rate independent and pays no cost when idle.
@MainActor
final class ContinuousCoalescer {
    private struct Key: Hashable { let contextID: String; let actionID: String }
    private struct Pending {
        var accumulatedMagnitude: Double
        var dispatch: @MainActor (Double) -> Void
    }

    private var pending: [Key: Pending] = [:]
    // `nonisolated(unsafe)` so `deinit` can read it without crossing actor boundaries.
    // Written only once in `installObserver()` before any concurrent access can occur.
    private nonisolated(unsafe) var observer: CFRunLoopObserver?

    init() {
        installObserver()
    }

    deinit {
        // `CFRunLoopRemoveObserver` is thread-safe; safe from a nonisolated deinit.
        if let observer {
            CFRunLoopRemoveObserver(CFRunLoopGetMain(), observer, .commonModes)
        }
    }

    /// Accumulate one continuous-shortcut event. If a previous event for the
    /// same (context, action) is pending in this run-loop pass, its
    /// `dispatch` closure is preserved and magnitudes are summed; otherwise
    /// the new `dispatch` is stored.
    func accumulate(
        contextID: String,
        actionID: String,
        magnitude: Double,
        dispatch: @escaping @MainActor (Double) -> Void
    ) {
        let key = Key(contextID: contextID, actionID: actionID)
        if pending[key] != nil {
            pending[key]!.accumulatedMagnitude += magnitude
            // Always use the latest dispatch closure so the most-recent call site's
            // capture context (e.g. the one that holds the `received` variable) wins.
            pending[key]!.dispatch = dispatch
        } else {
            pending[key] = Pending(accumulatedMagnitude: magnitude, dispatch: dispatch)
        }
    }

    // swiftlint:disable identifier_name
    /// Test hook: synchronously drain pending dispatches. Production code
    /// drives this from the run-loop observer.
    func __flush() {
        let snapshot = pending
        pending.removeAll(keepingCapacity: true)
        for (_, item) in snapshot {
            item.dispatch(item.accumulatedMagnitude)
        }
    }

    // swiftlint:enable identifier_name

    private func installObserver() {
        let observer = CFRunLoopObserverCreateWithHandler(
            kCFAllocatorDefault,
            CFRunLoopActivity.beforeWaiting.rawValue,
            true,
            0
        ) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.__flush() }
        }
        CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
        self.observer = observer
    }
}
