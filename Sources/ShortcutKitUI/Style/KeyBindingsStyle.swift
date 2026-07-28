import Foundation

/// Visual *density* for `KeyBindingsView` and the recorders inside it (the
/// containment axis is ``KeyBindingsPresentation``; this is the analog of the
/// legend's `LegendOptions.size`). Passed as an init parameter.
///
/// `.regular` matches macOS Settings spacing/typography. `.dense` tightens
/// vertical padding and recorder widths for power-user apps that want to fit
/// more rows on screen. The legend (`LegendStyle`) and hint HUD have their own
/// sizing and are unaffected.
public enum KeyBindingsStyle: Sendable, Hashable {
    case regular
    case dense
}
