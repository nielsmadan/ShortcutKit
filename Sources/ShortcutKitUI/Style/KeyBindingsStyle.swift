import Foundation

/// Visual density for `KeyBindingsView` and the recorders inside it. Passed as
/// an init parameter (parallel to `LegendStyle` on `KeyBindingsLegendView`).
///
/// `.native` matches macOS Settings spacing/typography. `.dense` tightens
/// vertical padding and recorder widths for power-user apps that want to fit
/// more rows on screen. The legend (`LegendStyle`) and hint HUD have their own
/// sizing and are unaffected.
public enum KeyBindingsStyle: Sendable, Hashable {
    case native
    case dense
}
