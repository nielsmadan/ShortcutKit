import ShortcutKit
import SwiftUI

/// A drop-in Settings view containing hint preferences and shortcut bindings.
@MainActor
public struct ShortcutPreferencesView: View {
    @ObservedObject public var registry: ShortcutRegistry
    private let style: KeyBindingsStyle
    private let showsHintToggle: Bool
    private let showsDescriptions: Bool
    @State private var resetAlertShown = false

    /// `showsHintToggle` includes the hint preference; `showsDescriptions` includes
    /// action descriptions below their names.
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
