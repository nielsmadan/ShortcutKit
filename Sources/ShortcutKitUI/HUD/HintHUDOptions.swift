import SwiftUI

/// Where the discoverability toast appears within the view the
/// `.shortcutHintHUD(...)` modifier is attached to. The nine fixed anchors map to
/// the corners/edges/centre of that view (typically the window content area); the
/// toast is inset slightly from the edge.
public enum HintHUDPlacement: Sendable, Hashable {
    case topLeading, top, topTrailing
    case leading, center, trailing
    case bottomLeading, bottom, bottomTrailing

    /// Anchored to the mouse pointer, clamped so the toast stays inside the view.
    /// Suited to the common case where the hint fires right after a mouse click on
    /// a button or menu — the tip appears next to where you just acted. Falls back
    /// to `.top` when the pointer is outside the view at fire time (e.g. a
    /// programmatic fire with the mouse parked in another window).
    case cursor
}

extension HintHUDPlacement {
    /// SwiftUI alignment for the fixed anchors; `.cursor` reuses `.top` as its
    /// out-of-bounds fallback alignment.
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

/// The HUD's display knobs — toast placement and per-toast duration — passed via
/// the modifier's `options:` parameter. A `Sendable` value (a struct, not an enum)
/// because it bundles several independent knobs; contrast the single-axis
/// `KeyBindingsStyle` / `LegendStyle` variant enums passed via `style:`.
public struct HintHUDOptions: Sendable, Hashable {
    /// Where the toast appears. Default `.topTrailing`.
    public var placement: HintHUDPlacement
    /// How long a single toast stays visible before fading. Default 2 seconds.
    /// Distinct from `HintPolicy`, which bounds how often a hint may *recur*.
    public var duration: Duration

    public init(placement: HintHUDPlacement = .topTrailing, duration: Duration = .seconds(2)) {
        self.placement = placement
        self.duration = duration
    }

    public static let `default` = HintHUDOptions()
}

/// The data behind one hint, handed to a custom toast builder (and reusable for
/// adopters rendering the cue their own way). `text` is the fully-localized
/// "Tip: <action> is bound to <shortcut>" string the built-in toast shows;
/// `actionName` and `shortcut` are the components, for custom layouts.
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
