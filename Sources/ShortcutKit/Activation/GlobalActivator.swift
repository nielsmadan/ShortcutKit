import Foundation
import ShortcutField

/// Stable identifier for a single binding (one shortcut on one action in one context).
/// Used by `GlobalActivator` implementations to track per-binding registration status.
public struct BindingID: Sendable, Hashable {
    public let contextID: String
    public let actionID: String
    public let bindingIndex: Int

    public init(contextID: String, actionID: String, bindingIndex: Int) {
        self.contextID = contextID
        self.actionID = actionID
        self.bindingIndex = bindingIndex
    }
}

/// One effective global binding: its `BindingID` and the shortcut registered
/// for it. Returned by `ShortcutRegistry.globalBindings()`.
public struct GlobalBinding: Sendable, Hashable {
    public let id: BindingID
    public let shortcut: Shortcut
    public init(id: BindingID, shortcut: Shortcut) {
        self.id = id
        self.shortcut = shortcut
    }
}

/// Outcome of an attempted global registration for a single binding.
public enum GlobalBindingStatus: Sendable, Equatable {
    case registered
    case failed(reason: FailureReason)
    case shadowedBySystem
    case unsupportedTrigger

    /// Why a global registration failed. Closed set so adopters can branch on
    /// the cause (the `Equatable` conformance is meaningful, unlike a free-form
    /// `String`).
    public enum FailureReason: Sendable, Equatable {
        /// `RegisterEventHotKey` rejected the combo at registration time
        /// (often already claimed by another app).
        case registrationRejected
        /// A previously-registered hotkey could not be re-registered (e.g. after
        /// a menu closed and `resumeAllHotKeys` failed to reclaim the combo).
        case reregistrationFailed
    }
}

/// Protocol implemented by Phase 3's `ShortcutKitGlobal` to register `.global`-scoped
/// shortcut contexts with the system. Core declares the protocol; no Carbon dependency
/// lives here.
@MainActor
public protocol GlobalActivator: AnyObject {
    func start(_ registry: ShortcutRegistry) throws
    func stop()
    var status: [BindingID: GlobalBindingStatus] { get }
}
