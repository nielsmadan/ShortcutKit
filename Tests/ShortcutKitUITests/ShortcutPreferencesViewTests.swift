@testable import ShortcutKit
@testable import ShortcutKitUI
import SwiftUI
import Testing

@MainActor
struct ShortcutPreferencesViewTests {
    enum Act: String, ShortcutAction {
        case save
        var definition: ShortcutActionDefinition { .init("Save", Shortcut("cmd+s")) }
    }

    @Test func preferencesViewExposesRegistry() {
        let ctx = ShortcutContext<Act>("editor")
        let reg = ShortcutRegistry(contexts: [ctx])
        let view = ShortcutPreferencesView(registry: reg)
        #expect(view.registryForTest === reg)
    }

    @Test func appStorageKeyMatchesHUD() {
        // Both ShortcutHintHUD and ShortcutPreferencesView use @AppStorage("shortcutkit.hintsEnabled").
        // We don't introspect SwiftUI's AppStorage, but document the contract via a constant test.
        #expect(ShortcutPreferencesView.hintsEnabledStorageKey == "shortcutkit.hintsEnabled")
    }
}
