import SwiftUI

/// Placement of a shortcut hint within its presentation host.
public enum HintHUDPlacement: Sendable, Hashable {
    case topLeading, top, topTrailing
    case leading, center, trailing
    case bottomLeading, bottom, bottomTrailing

    /// At the pointer, clamped inside the presentation host. Falls back to `.top` when unavailable.
    case cursor
}

/// Presentation transition for shortcut hints.
public enum HintHUDTransition: Sendable, Hashable {
    /// Scale and fade normally; fade only when Reduce Motion is enabled.
    case automatic
    case fade
    case scale
    case move(edge: Edge)
    case none
}

/// The coordinate space and window layer that hosts shortcut hints.
public enum HintHUDPresentation: Sendable, Hashable {
    /// Inside the modified SwiftUI view.
    case view
    /// Above the active application window, including its sheets.
    case window
    /// On the visible frame of the active application's screen.
    case screen
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

/// Presentation options for the shortcut hint HUD.
public struct HintHUDOptions: Sendable, Hashable {
    /// Where the toast appears. Default `.topTrailing`.
    public var placement: HintHUDPlacement
    /// Where the toast is hosted. Default ``HintHUDPresentation/view``.
    public var presentation: HintHUDPresentation
    /// How long a toast remains visible. Default two seconds.
    public var duration: Duration
    /// How a toast enters and leaves. Default ``HintHUDTransition/automatic``.
    public var transition: HintHUDTransition

    public init(
        placement: HintHUDPlacement = .topTrailing,
        presentation: HintHUDPresentation = .view,
        duration: Duration = .seconds(2),
        transition: HintHUDTransition = .automatic
    ) {
        self.placement = placement
        self.presentation = presentation
        self.duration = duration
        self.transition = transition
    }

    public static let `default` = HintHUDOptions()
}

/// Localized content supplied to a shortcut-hint style or custom view.
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
