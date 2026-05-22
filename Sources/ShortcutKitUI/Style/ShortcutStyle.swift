import Foundation

/// Visual flavor for `KeyBindingsView` and its sub-views.
///
/// `.native` matches macOS Settings spacing/typography. `.dense` tightens
/// vertical padding for power-user apps that want to fit more rows on screen.
public enum ShortcutStyle: Sendable, Hashable {
    case native
    case dense
}
