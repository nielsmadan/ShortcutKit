import ShortcutKit
import SwiftUI

/// Drop-in Settings-tab view composing the General preferences (hint toggle) and
/// the full `KeyBindingsView`. Reads `@AppStorage("shortcutkit.hintsEnabled")`,
/// the same key the HUD checks at runtime.
@MainActor
public struct ShortcutPreferencesView: View {
    public let registry: ShortcutRegistry

    /// Stable AppStorage key for the user-facing hint toggle. Public so adopters
    /// can read/write it from anywhere (e.g. their own preferences scene).
    public static let hintsEnabledStorageKey = "shortcutkit.hintsEnabled"

    /// Stable AppStorage key for the dense-style toggle.
    public static let denseStyleStorageKey = "shortcutkit.style.dense"

    @AppStorage("shortcutkit.hintsEnabled") private var hintsEnabled = true
    @AppStorage("shortcutkit.style.dense") private var denseStyle = false

    public init(registry: ShortcutRegistry) {
        self.registry = registry
    }

    var registryForTest: ShortcutRegistry { registry }

    public var body: some View {
        Form {
            Section("General") {
                Toggle("Show shortcut hints", isOn: $hintsEnabled)
                Toggle("Dense layout", isOn: $denseStyle)
            }
            Section("Shortcuts") {
                KeyBindingsView(registry: registry)
                    .shortcutStyle(denseStyle ? .dense : .native)
            }
        }
    }
}
