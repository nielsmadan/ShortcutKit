import Foundation

/// Rendering flavor for `KeyBindingsLegendView`.
public enum LegendStyle: Sendable, Hashable {
    /// Sheet-presentable, grouped by context. Suited to a Help → "Keyboard
    /// Shortcuts" menu item.
    case modal
    /// Sticky side-panel, grouped by context. Toggle it from the host app.
    case sidebar
    /// A single horizontal row of compact "⌘S Save · ⌘N New" entries.
    case compactStrip
}
