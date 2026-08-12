import ShortcutKit
import SwiftUI

/// Bare `Form` rows for enabling shortcut hints and choosing their frequency.
/// Place this view inside a host `Section`; it reads and writes the registry directly.
/// A current or default timeout policy appears as “Occasionally.”
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

    private var timeoutTag: HintPolicy? {
        if case .timeout = registry.hintFrequency { return registry.hintFrequency }
        if case .timeout = registry.defaultHintFrequency { return registry.defaultHintFrequency }
        return nil
    }
}
