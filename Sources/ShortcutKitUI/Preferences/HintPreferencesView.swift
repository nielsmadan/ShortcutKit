import ShortcutKit
import SwiftUI

/// The discoverability-hint preferences — a "show hints" toggle and, while hints
/// are on, a frequency picker — as bare `Form` rows. Place it inside your own
/// `Section` in a settings `Form` to sit the hint controls alongside other
/// preferences, instead of adopting the whole ``ShortcutPreferencesView`` pane.
///
/// Unlike `KeyBindingsView(presentation:.embedded)` (which brings its own
/// `Section`s), this emits row content only — the host supplies the `Section`.
///
/// Both controls read and write the registry (`hintsEnabled` / `hintFrequency`),
/// so this view stays in sync with the HUD and any other observer. The frequency
/// picker offers **Always**, **Once per session**, and — when the current value or
/// the app author's default is a `.timeout` — an **Occasionally** row.
@MainActor
public struct HintPreferencesView: View {
    @ObservedObject var registry: ShortcutRegistry

    public init(registry: ShortcutRegistry) {
        self.registry = registry
    }

    public var body: some View {
        Toggle(uiString("Show shortcut hints"), isOn: Binding(
            get: { registry.hintsEnabled },
            set: { registry.setHintsEnabled($0) }
        ))
        if registry.hintsEnabled {
            Picker(uiString("Hint frequency"), selection: Binding(
                get: { registry.hintFrequency },
                set: { registry.setHintFrequency($0) }
            )) {
                Text(uiString("Always")).tag(HintPolicy.always)
                Text(uiString("Once per session")).tag(HintPolicy.oncePerSession)
                if let timeoutTag {
                    Text(uiString("Occasionally")).tag(timeoutTag)
                }
            }
        }
    }

    /// The `.timeout` value to offer as the "Occasionally" row, if any. Prefers the
    /// current value when it's a timeout, so the picker selection always has a
    /// matching tag (no blank state); otherwise falls back to the app author's
    /// timeout default so a configured `.timeout` default stays reselectable after
    /// the user switches away from it.
    private var timeoutTag: HintPolicy? {
        if case .timeout = registry.hintFrequency { return registry.hintFrequency }
        if case .timeout = registry.defaultHintFrequency { return registry.defaultHintFrequency }
        return nil
    }
}
