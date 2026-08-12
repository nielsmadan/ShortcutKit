import SwiftUI

/// Placement of a shortcut hint within the modified view.
public enum HintHUDPlacement: Sendable, Hashable {
    case topLeading, top, topTrailing
    case leading, center, trailing
    case bottomLeading, bottom, bottomTrailing

    /// At the pointer, clamped inside the view. Falls back to `.top` when unavailable.
    case cursor
}

extension HintHUDPlacement {
    var alignment: Alignment {
        switch self {
        case .topLeading: .topLeading
        case .top: .top
        case .topTrailing: .topTrailing
        case .leading: .leading
        case .center: .center
        case .trailing: .trailing
        case .bottomLeading: .bottomLeading
        case .bottom: .bottom
        case .bottomTrailing: .bottomTrailing
        case .cursor: .top
        }
    }
}

/// Placement and duration options for the shortcut hint HUD.
public struct HintHUDOptions: Sendable, Hashable {
    /// Where the toast appears. Default `.topTrailing`.
    public var placement: HintHUDPlacement
    /// How long a toast remains visible. Default two seconds.
    public var duration: Duration

    public init(placement: HintHUDPlacement = .topTrailing, duration: Duration = .seconds(2)) {
        self.placement = placement
        self.duration = duration
    }

    public static let `default` = HintHUDOptions()
}

/// Localized content supplied to a custom shortcut-hint view.
/// `text` is the built-in message; `actionName` and `shortcut` support custom layouts.
public struct HintToastContext: Sendable, Hashable {
    public let actionName: String
    public let shortcut: String
    public let text: String

    public init(actionName: String, shortcut: String, text: String) {
        self.actionName = actionName
        self.shortcut = shortcut
        self.text = text
    }
}
