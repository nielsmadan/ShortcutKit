import AppKit
@testable import ShortcutKitUI
import SwiftUI
import Testing

@MainActor
struct LegendAppearanceTests {
    private let systemFamily = NSFont.systemFont(ofSize: 12).familyName
    private let monoSystemFamily = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular).familyName

    // MARK: - Slot defaults

    @Test func defaultShortcutFaceIsTheLegendMonospace() {
        // Family, not `fontName` — "Menlo" resolves to the PostScript "Menlo-Regular".
        let font = LegendAppearance.default.shortcutNSFont(defaultSize: 12)
        #expect(font.familyName == legendDefaultShortcutFontName)
        #expect(font.pointSize == 12)
    }

    @Test func defaultLabelAndHeaderFacesAreTheSystemFont() {
        #expect(LegendAppearance.default.labelNSFont(defaultSize: 12).familyName == systemFamily)
        #expect(LegendAppearance.default.headerNSFont(defaultSize: 9).familyName == systemFamily)
        #expect(LegendAppearance.default.headerNSFont(defaultSize: 9).pointSize == 9)
    }

    // MARK: - Size

    @Test func nilSizeInheritsTheLegendSizeMetric() {
        for metric in [CGFloat(10), 12, 14, 17] {
            var appearance = LegendAppearance.default
            appearance.labelFont = LegendFont(face: .named("Helvetica"))
            #expect(appearance.labelNSFont(defaultSize: metric).pointSize == metric)
        }
    }

    @Test func explicitSizeOverridesTheMetric() {
        var appearance = LegendAppearance.default
        appearance.labelFont = LegendFont(size: 30)
        appearance.shortcutFont = LegendFont(size: 30)
        #expect(appearance.labelNSFont(defaultSize: 12).pointSize == 30)
        #expect(appearance.shortcutNSFont(defaultSize: 12).pointSize == 30)
    }

    @Test func unusableSizesAreDiscardedRatherThanPassedToAppKit() {
        // AppKit silently substitutes its OWN default (13pt system / 12pt Menlo) for a
        // non-positive size, and aborts the process on a non-finite one — so neither may
        // reach it. Both must read back as nil and fall through to the metric.
        for bad in [CGFloat(0), -12, .nan, .infinity, -.infinity] {
            #expect(LegendFont(size: bad).size == nil)
            var appearance = LegendAppearance.default
            appearance.labelFont = LegendFont(size: bad)
            #expect(appearance.labelNSFont(defaultSize: 10).pointSize == 10)
        }
    }

    @Test func unusableSizesAreDiscardedOnAssignmentToo() {
        var font = LegendFont(size: 20)
        font.size = 0
        #expect(font.size == nil)
        font.size = .nan
        #expect(font.size == nil)
    }

    @Test func nanSizeCannotBreakEquality() {
        // A stored NaN would make `LegendOptions != itself` (nan != nan), defeating the
        // SwiftUI diffing that `appearanceParticipatesInOptionsEquality` depends on.
        let font = LegendFont(size: .nan)
        #expect(font == font)
        var options = LegendOptions()
        options.appearance.labelFont = LegendFont(size: .nan)
        #expect(options == options)
    }

    // MARK: - Faces

    @Test func namedFaceResolvesWhenInstalled() {
        var appearance = LegendAppearance.default
        appearance.labelFont = LegendFont(face: .named("Helvetica"))
        appearance.shortcutFont = LegendFont(face: .named("Helvetica"))
        #expect(appearance.labelNSFont(defaultSize: 12).fontName == "Helvetica")
        #expect(appearance.shortcutNSFont(defaultSize: 12).fontName == "Helvetica")
    }

    @Test func missingShortcutFaceFallsBackToTheSlotsBuiltInMonospace() {
        // Pin the family, not just `isFixedPitch` — Menlo is fixed-pitch too, so an
        // `isFixedPitch` assertion alone can't tell a correct fallback from a wrong one.
        var appearance = LegendAppearance.default
        appearance.shortcutFont = LegendFont(face: .named("NoSuchFontXYZ"))
        let font = appearance.shortcutNSFont(defaultSize: 12)
        #expect(font.familyName == legendDefaultShortcutFontName)
        #expect(font.pointSize == 12)
    }

    @Test func missingLabelFaceFallsBackToSystem() {
        var appearance = LegendAppearance.default
        appearance.labelFont = LegendFont(face: .named("NoSuchFontXYZ"))
        let font = appearance.labelNSFont(defaultSize: 12)
        #expect(font.familyName == systemFamily)
        #expect(font.pointSize == 12)
    }

    @Test func monospacedSystemFaceIsHonoredNotFallenBackTo() {
        // Distinguishing this from the fallback path needs the family: both are
        // fixed-pitch, and the fallback yields Menlo.
        var appearance = LegendAppearance.default
        appearance.shortcutFont = LegendFont(face: .monospacedSystem())
        let font = appearance.shortcutNSFont(defaultSize: 12)
        #expect(font.familyName == monoSystemFamily)
        #expect(font.familyName != legendDefaultShortcutFontName)
    }

    @Test func systemFaceOnTheShortcutSlotIsProportional() {
        // Documented trade, pinned so it stays deliberate: `.system` opts the shortcut
        // column out of the monospace, and the column stops lining up.
        var appearance = LegendAppearance.default
        appearance.shortcutFont = LegendFont(face: .system())
        let font = appearance.shortcutNSFont(defaultSize: 12)
        #expect(font.isFixedPitch == false)
        #expect(font.familyName == systemFamily)
    }

    // MARK: - Weight

    @Test func weightIsHonoredOnEverySlotThatAcceptsIt() {
        // Weight lives on the Face cases that can honor it, so it can no longer be set
        // on a named face and silently dropped. Both system faces must apply it, on the
        // shortcut slot as well as the label slot.
        var appearance = LegendAppearance.default
        appearance.labelFont = LegendFont(face: .system(weight: .bold))
        appearance.shortcutFont = LegendFont(face: .monospacedSystem(weight: .bold))
        let boldLabel = appearance.labelNSFont(defaultSize: 12)
        let boldShortcut = appearance.shortcutNSFont(defaultSize: 12)
        #expect(boldLabel.fontName != NSFont.systemFont(ofSize: 12, weight: .regular).fontName)
        #expect(boldShortcut.fontName != NSFont.monospacedSystemFont(ofSize: 12, weight: .regular).fontName)
    }

    // MARK: - Colors

    @Test func defaultForegroundsAreStableAcrossAccesses() {
        // `AnyShapeStyle` boxes into a class and isn't Equatable, so a freshly boxed
        // value per access makes SwiftUI's modifier comparison fail every body pass.
        // The no-override path must hand back the same box.
        #expect(MemoryLayout<AnyShapeStyle>.size == 8, "box-identity probe assumes a single reference word")
        let appearance = LegendAppearance.default
        #expect(boxIdentity(appearance.shortcutForeground) == boxIdentity(appearance.shortcutForeground))
        #expect(boxIdentity(appearance.labelForeground) == boxIdentity(appearance.labelForeground))
        #expect(boxIdentity(appearance.headerForeground) == boxIdentity(appearance.headerForeground))
    }

    @Test func overriddenForegroundsReplaceTheDefaults() {
        var appearance = LegendAppearance.default
        appearance.shortcutColor = .red
        appearance.labelColor = .green
        appearance.headerColor = .blue
        #expect(boxIdentity(appearance.shortcutForeground) != boxIdentity(LegendAppearance.default.shortcutForeground))
        #expect(boxIdentity(appearance.labelForeground) != boxIdentity(LegendAppearance.default.labelForeground))
        #expect(boxIdentity(appearance.headerForeground) != boxIdentity(LegendAppearance.default.headerForeground))
    }

    @Test func eachColorSlotIsIndependent() {
        var appearance = LegendAppearance.default
        appearance.labelColor = .red
        #expect(boxIdentity(appearance.shortcutForeground) == boxIdentity(LegendAppearance.default.shortcutForeground))
        #expect(boxIdentity(appearance.headerForeground) == boxIdentity(LegendAppearance.default.headerForeground))
    }

    private func boxIdentity(_ style: AnyShapeStyle) -> UInt {
        withUnsafeBytes(of: style) { $0.load(as: UInt.self) }
    }

    // MARK: - Geometry

    @Test func columnWidthsTrackAnExplicitFontSize() {
        // `cellWidth` is public and adopters size containers from it, so it must not
        // report metric-sized columns for a legend rendering at a larger font.
        var options = LegendOptions(size: .small)
        let base = options.cellWidth
        options.appearance.labelFont = LegendFont(size: options.metrics.entryFont * 2)
        #expect(legendColumnScale(for: options) == 2)
        #expect(options.cellWidth > base)
    }

    @Test func columnWidthsAreUnchangedForTheDefaultAppearance() {
        for size in LegendSize.allCases {
            let options = LegendOptions(size: size)
            #expect(legendColumnScale(for: options) == 1)
            #expect(options.cellWidth == options.metrics.cellWidth)
        }
    }

    @Test func columnWidthsNeverShrinkBelowTheMetric() {
        // A smaller explicit font must not narrow the columns — the shortcut column is
        // sized for glyph content, not just point size.
        var options = LegendOptions(size: .large)
        options.appearance.labelFont = LegendFont(size: 4)
        #expect(legendColumnScale(for: options) == 1)
    }

    // MARK: - Options integration

    @Test func optionsDefaultToTheBuiltInAppearance() {
        #expect(LegendOptions.default.appearance == .default)
    }

    @Test func appearanceParticipatesInOptionsEquality() {
        // `LegendOptions` is Hashable and feeds SwiftUI's diffing, so an appearance
        // change has to register as a change.
        var tweaked = LegendOptions()
        tweaked.appearance.labelColor = .red
        #expect(tweaked != LegendOptions.default)

        var refaced = LegendOptions()
        refaced.appearance.headerFont = LegendFont(face: .named("Helvetica"))
        #expect(refaced != LegendOptions.default)
    }
}
