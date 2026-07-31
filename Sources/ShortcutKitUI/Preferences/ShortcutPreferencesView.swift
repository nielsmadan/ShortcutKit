import ShortcutKit
import SwiftUI

/// Drop-in Settings-tab view: the General preferences (hint toggle) and the
/// shortcut lists, in a native grouped `Form`. Composes `KeyBindingsView` in its
/// `.embedded` presentation so everything shares one scroll and the system
/// grouped styling. The hint toggle reads/writes `registry.hintsEnabled`,
/// persisted through the registry's store — the same value the HUD checks.
@MainActor
public struct ShortcutPreferencesView: View {
    @ObservedObject public var registry: ShortcutRegistry
    private let style: KeyBindingsStyle
    private let showsHintToggle: Bool
    @State private var resetAlertShown = false

    /// `style` is the app author's density choice (consumer apps `.regular`,
    /// power-user apps `.dense`) — not a user setting. `showsHintToggle` controls
    /// whether the "Show shortcut hints" toggle is offered at all. The hint
    /// preference persists through the registry's store (set the registry's
    /// `defaultHintsEnabled` for the off-by-default case).
    public init(
        registry: ShortcutRegistry,
        style: KeyBindingsStyle = .regular,
        showsHintToggle: Bool = true
    ) {
        self.registry = registry
        self.style = style
        self.showsHintToggle = showsHintToggle
    }

    var registryForTest: ShortcutRegistry { registry }

    public var body: some View {
        Form {
            if showsHintToggle {
                Section(uiString("General")) {
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
                            // The named rows can't represent an arbitrary interval, so
                            // when the app author's default is a `.timeout` offer it as a
                            // stable, always-reselectable row (driven by the default, not
                            // the current value, so it survives switching away and back).
                            if case .timeout = registry.defaultHintFrequency {
                                Text(uiString("Occasionally")).tag(registry.defaultHintFrequency)
                            }
                        }
                    }
                }
            }
            KeyBindingsView(registry: registry, style: style, presentation: .embedded)
            // `.embedded` leaves Reset-All to the host; this drop-in provides it.
            // (A search field, if wanted, is likewise the host's to add — e.g.
            // `.searchable` on this Form.)
            Section {
                Button(uiString("Reset All…"), role: .destructive) { resetAlertShown = true }
            }
        }
        .formStyle(.grouped)
        .alert(uiString("Reset all shortcuts to defaults?"), isPresented: $resetAlertShown) {
            Button(uiString("Cancel"), role: .cancel) {}
            Button(uiString("Reset"), role: .destructive) { registry.resetAll() }
        } message: {
            Text(uiString("This will discard all customisations across every context."))
        }
    }
}
