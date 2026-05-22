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

/// Outcome of an attempted global registration for a single binding.
public enum GlobalBindingStatus: Sendable {
    case registered
    case failed(reason: String)
    case shadowedBySystem
    case unsupportedTrigger
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
