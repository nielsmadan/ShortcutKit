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

    @Test func hintToggleRoutesThroughRegistry() {
        let ctx = ShortcutContext<Act>("editor")
        let reg = ShortcutRegistry(contexts: [ctx])
        #expect(reg.hintsEnabled == true)
        reg.setHintsEnabled(false)
        #expect(reg.hintsEnabled == false)
    }

    @Test func hintPreferencesViewBindsRegistry() {
        let ctx = ShortcutContext<Act>("editor")
        let reg = ShortcutRegistry(contexts: [ctx])
        #expect(HintPreferencesView(registry: reg).registry === reg)
    }
}
