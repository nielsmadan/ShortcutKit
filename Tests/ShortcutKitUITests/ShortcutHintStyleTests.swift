@testable import ShortcutKitUI
import SwiftUI
import Testing

@MainActor
struct ShortcutHintStyleTests {
    @Test func builtInStylePreservesTheExistingToastDefaults() {
        let style = ShortcutHintToastStyle()
        #expect(style.size == .automatic)
        #expect(style.font == nil)
        #expect(style.textColor == nil)
        #expect(style.backgroundColor == nil)
        #expect(style.container == .roundedRectangle)
    }

    @Test func builtInStyleOverridesAreIndependent() {
        let style = ShortcutHintToastStyle(
            size: .small,
            font: .headline,
            textColor: .red,
            backgroundColor: .blue,
            container: .capsule
        )
        #expect(style.size == .small)
        #expect(style.font == .headline)
        #expect(style.textColor == .red)
        #expect(style.backgroundColor == .blue)
        #expect(style.container == .capsule)
    }

    @Test func defaultColorsRespectTheColorScheme() {
        let style = ShortcutHintToastStyle()

        let lightColors = style.resolvedColors(for: .light)
        #expect(lightColors.foreground == Color(white: 0.12))
        #expect(lightColors.background == Color(white: 0.97))
        #expect(lightColors.border == Color.black.opacity(0.15))
        #expect(lightColors.borderWidth == 1)

        let darkColors = style.resolvedColors(for: .dark)
        #expect(darkColors.foreground == .white)
        #expect(darkColors.background == Color(white: 0.12))
        #expect(darkColors.border == Color.white.opacity(0.18))
        #expect(darkColors.borderWidth == 1)
    }

    @Test func explicitColorsOverrideTheAdaptiveDefaults() {
        let style = ShortcutHintToastStyle(textColor: .red, backgroundColor: .blue)
        let colors = style.resolvedColors(for: .dark)

        #expect(colors.foreground == .red)
        #expect(colors.background == .blue)
    }

    @Test func builtInTextEmphasizesTheActionAndShortcut() throws {
        let text = emphasizedHintText(HintToastContext(
            actionName: "Rename Session",
            shortcut: "⌘R",
            text: "Tip: Rename Session is bound to ⌘R"
        ))
        let actionRange = try #require(text.range(of: "Rename Session"))
        let shortcutRange = try #require(text.range(of: "⌘R"))

        #expect(text[actionRange].inlinePresentationIntent == .stronglyEmphasized)
        #expect(text[shortcutRange].inlinePresentationIntent == .stronglyEmphasized)
    }

    @Test func allBuiltInSizesAreDistinctCases() {
        #expect(ShortcutHintSize.allCases == [.automatic, .small, .medium, .large, .extraLarge])
    }

    @Test func test_DocExample_shortcutHintStyle() {
        let view = Color.clear.shortcutHintStyle(
            .toast(
                font: .system(size: 13, weight: .medium),
                textColor: .white,
                backgroundColor: .indigo
            )
        )
        _ = view
    }

    @Test func customStylesReceiveThePublicConfiguration() {
        let view = Color.clear.shortcutHintStyle(ActionNameHintStyle())
        _ = view
    }
}

private struct ActionNameHintStyle: ShortcutHintStyle {
    func makeBody(configuration: Configuration) -> some View {
        Text(configuration.actionName)
    }
}
