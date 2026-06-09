import ShortcutKit
import SwiftUI

/// Drop-in Settings-tab view composing the General preferences (hint toggle) and
/// the full `KeyBindingsView`. The hint toggle reads/writes `registry.hintsEnabled`,
/// persisted through the registry's store — the same value the HUD checks.
@MainActor
public struct ShortcutPreferencesView: View {
    @ObservedObject public var registry: ShortcutRegistry
    private let style: KeyBindingsStyle
    private let searchEnabled: Bool
    private let contextLayout: ContextLayout
    private let showsHintToggle: Bool

    /// `style` is the app author's density choice (consumer apps `.native`,
    /// power-user apps `.dense`) — not a user setting. `showsHintToggle` controls
    /// whether the "Show shortcut hints" toggle is offered at all. `searchEnabled`
    /// and `contextLayout` are forwarded to the embedded `KeyBindingsView`. The
    /// hint preference persists through the registry's store (set the registry's
    /// `defaultHintsEnabled` for the off-by-default case).
    public init(
        registry: ShortcutRegistry,
        style: KeyBindingsStyle = .native,
        searchEnabled: Bool = true,
        contextLayout: ContextLayout = .stacked,
        showsHintToggle: Bool = true
    ) {
        self.registry = registry
        self.style = style
        self.searchEnabled = searchEnabled
        self.contextLayout = contextLayout
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
                }
            }
            Section(uiString("Shortcuts")) {
                KeyBindingsView(
                    registry: registry,
                    style: style,
                    searchEnabled: searchEnabled,
                    contextLayout: contextLayout
                )
            }
        }
    }
}
