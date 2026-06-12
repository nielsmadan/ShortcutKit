/// The dispatch flavour passed to a context's closure.
public enum ShortcutDispatch: Sendable, Equatable {
    /// A discrete action fired once.
    case discrete
    /// A continuous action; `magnitude` is the gesture delta accumulated since
    /// the previous tick (matcher-driven), or `1.0` for adopter-driven
    /// `dispatch(_:)` of a continuous action.
    case continuous(magnitude: Double)
}

/// Emitted on `actionFired` whenever an action runs — adopter-driven or matcher-driven.
public struct ActionFiredEvent: Sendable, Hashable {
    /// What caused this action to fire.
    public enum Source: Sendable, Hashable {
        /// The matcher fired from a real shortcut event.
        case shortcut
        /// An adopter called `dispatch(_:)` or `notify(_:)` programmatically.
        case programmatic
    }

    public let contextID: String
    public let actionID: String
    public let source: Source

    public init(contextID: String, actionID: String, source: Source) {
        self.contextID = contextID
        self.actionID = actionID
        self.source = source
    }
}
