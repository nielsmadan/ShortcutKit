import Foundation
@testable import ShortcutKitUI
import Testing

@MainActor
struct LocalizationTests {
    @Test func englishLocalizationIsPackaged() {
        // Confirms the String resource shipped in Bundle.module (not just the
        // key-fallback path).
        #expect(shortcutKitUILocalizations().contains("en"))
    }

    @Test func chromeStringsResolveAgainstPackageBundle() {
        #expect(uiString("Reset All…") == "Reset All…")
        #expect(uiString("Duplicate binding") == "Duplicate binding")
        // Previously rendered verbatim (non-localizable); now a real key.
        #expect(uiString("Global shortcuts can't be chords") == "Global shortcuts can't be chords")
    }

    @Test func interpolatedTemplatesSubstitute() {
        #expect(uiString("Blocker: \("save")") == "Blocker: save")
        #expect(uiString("Tip: \("Save") is bound to \("⌘S")") == "Tip: Save is bound to ⌘S")
    }
}
