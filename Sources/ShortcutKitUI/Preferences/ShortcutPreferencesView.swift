import ShortcutKit
import SwiftUI

/// Drop-in Settings-tab view composing the General preferences (hint toggle) and
/// the full `KeyBindingsView`. Reads the `hintsEnabled` preference
/// (`ShortcutPreferencesView.hintsEnabledStorageKey`), the same key the HUD
/// checks at runtime.
@MainActor
public struct ShortcutPreferencesView: View {
    public let registry: ShortcutRegistry
    private let searchEnabled: Bool
    private let contextLayout: ContextLayout

    /// Stable AppStorage key for the user-facing hint toggle. Public so adopters
    /// can read/write it from anywhere (e.g. their own preferences scene).
    public static let hintsEnabledStorageKey = "shortcutkit.hintsEnabled"

    /// Stable AppStorage key for the dense-style toggle.
    public static let denseStyleStorageKey = "shortcutkit.style.dense"

    @AppStorage(Self.hintsEnabledStorageKey) private var hintsEnabled = true
    @AppStorage(Self.denseStyleStorageKey) private var denseStyle = false

    /// `searchEnabled` and `contextLayout` are forwarded to the embedded
    /// `KeyBindingsView` — pass `.picker` for apps with many contexts.
    public init(
        registry: ShortcutRegistry,
        searchEnabled: Bool = true,
        contextLayout: ContextLayout = .stacked
    ) {
        self.registry = registry
        self.searchEnabled = searchEnabled
        self.contextLayout = contextLayout
    }

    var registryForTest: ShortcutRegistry { registry }

    public var body: some View {
        Form {
            Section("General") {
                Toggle("Show shortcut hints", isOn: $hintsEnabled)
                Toggle("Dense layout", isOn: $denseStyle)
            }
            Section("Shortcuts") {
                KeyBindingsView(
                    registry: registry,
                    style: denseStyle ? .dense : .native,
                    searchEnabled: searchEnabled,
                    contextLayout: contextLayout
                )
            }
        }
    }
}
