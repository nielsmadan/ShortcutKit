import Foundation

/// How `KeyBindingsLegendView` is *contained*. Orthogonal to the layout of the
/// entries themselves — columns, cell order, size, and the `compact` flag all
/// live in `LegendOptions` and apply to either container.
public enum LegendStyle: Sendable, Hashable {
    /// A material-backed, content-sized card. Suited to a docked side rail or
    /// inspector panel you keep on screen.
    case panel
    /// A chrome-free, scrolling container. Suited to a sheet, popover, or
    /// Help → "Keyboard Shortcuts" overlay that may grow taller than the space.
    case sheet
}
