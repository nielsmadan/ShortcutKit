import Foundation

/// Rendering flavor for `KeyBindingsLegendView`.
public enum LegendStyle: Sendable, Hashable {
    /// Sheet-presentable, grouped by context. Suited to Help → "Keyboard Shortcuts" menu items.
    case modal
    /// Sticky side-panel. Toggleable from the host app. Phase 2 Task 17.
    case sidebar
    /// Single horizontal row of compact "⌘S Save · ⌘N New" entries. Phase 2 Task 17.
    case compactStrip
}
