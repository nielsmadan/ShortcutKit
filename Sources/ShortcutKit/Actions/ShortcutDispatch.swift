/// The dispatch flavour passed to a context's closure.
public enum ShortcutDispatch: Sendable, Equatable {
    /// A discrete action fired once. Adopter-driven `dispatch(_:)` always uses this.
    case discrete
    /// A continuous action coalesced to one tick; `magnitude` is the gesture
    /// delta accumulated since the previous tick.
    case continuous(magnitude: Double)
}

/// Emitted on `actionFired` whenever an action runs — adopter-driven or matcher-driven.
public struct ActionFiredEvent: Sendable, Equatable {
    public let contextID: String
    public let actionID: String
    /// `true` if the matcher fired this action; `false` for `dispatch(_:)` / `notify(_:)`.
    public let viaShortcut: Bool

    public init(contextID: String, actionID: String, viaShortcut: Bool) {
        self.contextID = contextID
        self.actionID = actionID
        self.viaShortcut = viaShortcut
    }
}
