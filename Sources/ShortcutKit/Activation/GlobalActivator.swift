import Foundation
import ShortcutField

/// Stable identifier for one shortcut binding.
public struct BindingID: Sendable, Hashable {
    public let contextID: String
    public let actionID: String
    public let bindingIndex: Int

    public init(contextID: String, actionID: String, bindingIndex: Int) {
        self.contextID = contextID
        self.actionID = actionID
        self.bindingIndex = bindingIndex
    }

    /// The action reference without the binding index.
    public var ref: ActionRef { ActionRef(contextID: contextID, actionID: actionID) }
}

/// An effective shortcut eligible for global registration.
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

    /// Why global registration failed.
    public enum FailureReason: Sendable, Equatable {
        /// `RegisterEventHotKey` rejected the combo at registration time
        /// (often already claimed by another app).
        case registrationRejected
        /// A previously-registered hotkey could not be re-registered (e.g. after
        /// a menu closed and `resumeAllHotKeys` failed to reclaim the combo).
        case reregistrationFailed
    }
}

/// Registers `.global` shortcut contexts with the system.
@MainActor
public protocol GlobalActivator: AnyObject {
    func start(_ registry: ShortcutRegistry) throws
    func stop()
    var status: [BindingID: GlobalBindingStatus] { get }
}
