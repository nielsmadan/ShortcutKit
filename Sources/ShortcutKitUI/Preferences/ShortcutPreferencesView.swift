import ShortcutKit
import SwiftUI

/// Drop-in Settings-tab view: the General preferences (via ``HintPreferencesView``)
/// and the shortcut lists, in a native grouped `Form`. Composes `KeyBindingsView`
/// in its `.embedded` presentation so everything shares one scroll and the system
/// grouped styling.
@MainActor
public struct ShortcutPreferencesView: View {
    @ObservedObject public var registry: ShortcutRegistry
    private let style: KeyBindingsStyle
    private let showsHintToggle: Bool
    private let showsDescriptions: Bool
    @State private var resetAlertShown = false

    /// `style` is the app author's density choice (consumer apps `.regular`,
    /// power-user apps `.dense`) — not a user setting. `showsHintToggle` controls
    /// whether the "Show shortcut hints" toggle is offered at all; `showsDescriptions`
    /// renders each action's `description` (when it has one) as a subtitle. The hint
    /// preference persists through the registry's store (set the registry's
    /// `defaultHintsEnabled` for the off-by-default case).
    public init(
        registry: ShortcutRegistry,
        style: KeyBindingsStyle = .regular,
        showsHintToggle: Bool = true,
        showsDescriptions: Bool = false
    ) {
        self.registry = registry
        self.style = style
        self.showsHintToggle = showsHintToggle
        self.showsDescriptions = showsDescriptions
    }

    var registryForTest: ShortcutRegistry { registry }

    public var body: some View {
        Form {
            if showsHintToggle {
                Section(uiString("General")) {
                    HintPreferencesView(registry: registry)
                }
            }
            KeyBindingsView(
                registry: registry, style: style, presentation: .embedded,
                showsDescriptions: showsDescriptions
            )
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
