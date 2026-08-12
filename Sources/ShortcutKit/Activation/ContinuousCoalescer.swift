import CoreFoundation
import Foundation

/// Coalesces continuous shortcut events by action once per run-loop pass.
@MainActor
final class ContinuousCoalescer {
    private struct Key: Hashable { let contextID: String; let actionID: String }
    private struct Pending {
        var accumulatedMagnitude: Double
        var dispatch: @MainActor (Double) -> Void
    }

    private var pending: [Key: Pending] = [:]
    // Written once before use; `nonisolated(unsafe)` permits cleanup from `deinit`.
    private nonisolated(unsafe) var observer: CFRunLoopObserver?

    init() {
        installObserver()
    }

    deinit {
        // CFRunLoopRemoveObserver is thread-safe from a nonisolated deinitializer.
        if let observer {
            CFRunLoopRemoveObserver(CFRunLoopGetMain(), observer, .commonModes)
        }
    }

    /// Accumulates magnitudes for an action until the current run-loop pass ends.
    func accumulate(
        contextID: String,
        actionID: String,
        magnitude: Double,
        dispatch: @escaping @MainActor (Double) -> Void
    ) {
        let key = Key(contextID: contextID, actionID: actionID)
        if pending[key] != nil {
            pending[key]!.accumulatedMagnitude += magnitude
            pending[key]!.dispatch = dispatch
        } else {
            pending[key] = Pending(accumulatedMagnitude: magnitude, dispatch: dispatch)
        }
    }

    // swiftlint:disable identifier_name
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
