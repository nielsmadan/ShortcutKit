import SwiftUI

private struct ShortcutStyleKey: EnvironmentKey {
    static let defaultValue: ShortcutStyle = .native
}

public extension EnvironmentValues {
    /// Current shortcut UI style. Read in views that render shortcut rows /
    /// recorders to switch between native and dense spacing.
    var shortcutStyle: ShortcutStyle {
        get { self[ShortcutStyleKey.self] }
        set { self[ShortcutStyleKey.self] = newValue }
    }
}

public extension View {
    /// Set the shortcut UI style for this view and its descendants.
    func shortcutStyle(_ style: ShortcutStyle) -> some View {
        environment(\.shortcutStyle, style)
    }
}
