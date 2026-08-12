import Foundation

/// Errors thrown for invalid `CarbonGlobalActivator` lifecycle calls.
/// Per-binding failures are reported through `GlobalActivator.status`.
public enum GlobalActivatorError: Error, LocalizedError, Sendable {
    /// `start(_:)` was called on an activator that is already running.
    case alreadyStarted

    public var errorDescription: String? {
        switch self {
        case .alreadyStarted:
            "The global activator is already started. Call stop() before start()."
        }
    }
}
