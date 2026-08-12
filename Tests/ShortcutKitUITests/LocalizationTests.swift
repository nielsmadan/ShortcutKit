import Foundation
@testable import ShortcutKitUI
import Testing

@MainActor
struct LocalizationTests {
    @Test func englishLocalizationIsPackaged() {
        #expect(shortcutKitUILocalizations().contains("en"))
    }

    @Test func chromeStringsResolveAgainstPackageBundle() {
        #expect(uiString("Reset All…") == "Reset All…")
        #expect(uiString("Duplicate binding") == "Duplicate binding")
        #expect(uiString("Global shortcuts can't be chords") == "Global shortcuts can't be chords")
    }

    @Test func interpolatedTemplatesSubstitute() {
        #expect(uiString("Blocker: \("save")") == "Blocker: save")
        #expect(uiString("Tip: \("Save") is bound to \("⌘S")") == "Tip: Save is bound to ⌘S")
    }
}
