import AppKit
import SwiftUI

/// Menlo, not the system monospace: it slashes `0` and tails lowercase `l`, so
/// `0`/`O` and `l`/`I` stay apart in a key legend, and it's the only macOS-bundled
/// monospace with real ⌘⇧⌥⌃⌫⏎↩⇥ glyphs — the others fall back per-glyph and break
/// the advance grid.
let legendDefaultShortcutFontName = "Menlo"

/// One font slot in the legend.
///
/// A value type rather than an `NSFont` for two reasons: ``LegendOptions`` must stay
/// `Sendable` (neither `NSFont` nor `NSFontDescriptor` is), and the legend needs to
/// both *render* the font and *measure* it — the columns are fixed-width and the
/// hover tooltips are gated on a truncation measurement, and SwiftUI's `Font` is
/// opaque (it converts from `NSFont` but never back).
///
/// Both fields are `nil` by default and `nil` means "inherit", so overriding one
/// thing keeps the rest:
/// ```swift
/// LegendFont(face: .named("Inter"))          // host's face, legend's size
/// ```
public struct LegendFont: Sendable, Hashable {
    /// Which typeface fills the slot. Weight lives on the cases that can honor it —
    /// a named face carries its own, so name the weighted variant.
    public enum Face: Sendable, Hashable {
        /// The system font. Proportional: on ``LegendAppearance/shortcutFont`` this
        /// replaces the monospace, and key glyphs stop lining up between rows.
        case system(weight: NSFont.Weight = .regular)
        /// The system monospace (SF Mono). Note it lacks `↩` and `⇥` glyphs, which
        /// then fall back per-glyph and break the shortcut column's advance grid.
        case monospacedSystem(weight: NSFont.Weight = .regular)
        /// A PostScript or family name, e.g. `"Inter"` or `"Inter-SemiBold"`. Falls
        /// back to the slot's built-in face when the font isn't installed.
        case named(String)
    }

    /// `nil` (the default) keeps the slot's built-in face — the system font for the
    /// label and header, `Menlo` for the shortcut column.
    public var face: Face?

    /// Point size. `nil` (the default) keeps the ``LegendSize`` metric, so `size`
    /// still scales the whole legend coherently.
    ///
    /// Note an explicit size does *not* re-derive the fixed column widths from
    /// scratch — they scale with it proportionally, which keeps the columns sane but
    /// is not a measurement. Prefer ``LegendSize`` when you just want a bigger legend.
    /// Non-finite and non-positive values are discarded and read back as `nil`.
    public var size: CGFloat? {
        get { rawSize }
        set { rawSize = Self.sanitized(newValue) }
    }

    private var rawSize: CGFloat?

    public init(face: Face? = nil, size: CGFloat? = nil) {
        self.face = face
        rawSize = Self.sanitized(size)
    }

    /// A non-finite size reaches AppKit text layout and aborts the process; a
    /// non-positive one makes AppKit substitute *its* default (13pt/12pt) rather than
    /// the legend's metric. `.nan` additionally breaks `Hashable` (`nan != nan`),
    /// which would make `LegendOptions` unequal to itself and defeat SwiftUI diffing.
    private static func sanitized(_ size: CGFloat?) -> CGFloat? {
        guard let size, size.isFinite, size > 0 else { return nil }
        return size
    }

    /// The slot's built-in font, unchanged.
    public static let `default` = LegendFont()
}

extension LegendFont {
    /// Which built-in face a slot falls back to — both when `face` is `nil` and when
    /// a named face isn't installed. Two cases rather than a `Face`, so a call site
    /// can't ask for a fallback the resolver doesn't implement.
    enum Slot {
        case proportional
        case monospaced

        func builtIn(size: CGFloat) -> NSFont {
            switch self {
            case .proportional:
                .systemFont(ofSize: size, weight: .regular)
            case .monospaced:
                NSFont(name: legendDefaultShortcutFontName, size: size)
                    ?? .monospacedSystemFont(ofSize: size, weight: .regular)
            }
        }
    }

    func nsFont(slot: Slot, defaultSize: CGFloat) -> NSFont {
        let points = size ?? defaultSize
        guard let face else { return slot.builtIn(size: points) }
        switch face {
        case let .system(weight):
            return .systemFont(ofSize: points, weight: weight)
        case let .monospacedSystem(weight):
            return .monospacedSystemFont(ofSize: points, weight: weight)
        case let .named(name):
            return NSFont(name: name, size: points) ?? slot.builtIn(size: points)
        }
    }
}

/// Fonts and colors for ``KeyBindingsLegendView``, so a legend can adopt a host
/// app's type stack instead of forcing the system font.
///
/// Every field defaults to the legend's built-in look, so override only what differs:
/// ```swift
/// var options = LegendOptions()
/// options.appearance.labelFont = LegendFont(face: .named("Inter"))
/// ```
///
/// This covers restyling, not restructuring. For a legend laid out differently than
/// the shortcut/label pair, read the data from Core (`shortcuts(for:)`,
/// `displayStrings(for:)`) and build the view yourself.
///
/// The legend is fixed-size by design — it does not scale with Dynamic Type, because
/// the columns are measured with the same font they render and a scaled render
/// against an unscaled measurement mis-fires the truncation tooltips. Use
/// ``LegendSize`` (or ``LegendFont/size``) to resize it.
public struct LegendAppearance: Sendable, Hashable {
    /// Entry label — the action's name. Pairs with ``labelColor``.
    public var labelFont: LegendFont
    /// The shortcut column. Monospaced by default so key glyphs line up between rows;
    /// a proportional face here (including ``LegendFont/Face/system(weight:)``) gives
    /// that up.
    public var shortcutFont: LegendFont
    /// Group headers (uppercased, above the rule).
    public var headerFont: LegendFont
    /// `nil` keeps the built-in `.primary` — the shortcut is the emphasized half
    /// of the pair. An explicit `Color` is flat, so it forfeits the hierarchical
    /// vibrancy treatment inside the ``LegendStyle/panel`` material.
    public var shortcutColor: Color?
    /// `nil` keeps the built-in 75%-primary, between the shortcut and the header.
    public var labelColor: Color?
    /// `nil` keeps the built-in `.secondary`. Flat overrides forfeit vibrancy, as
    /// with ``shortcutColor``.
    public var headerColor: Color?

    public init(
        labelFont: LegendFont = .default,
        shortcutFont: LegendFont = .default,
        headerFont: LegendFont = .default,
        shortcutColor: Color? = nil,
        labelColor: Color? = nil,
        headerColor: Color? = nil
    ) {
        self.labelFont = labelFont
        self.shortcutFont = shortcutFont
        self.headerFont = headerFont
        self.shortcutColor = shortcutColor
        self.labelColor = labelColor
        self.headerColor = headerColor
    }

    public static let `default` = LegendAppearance()
}

extension LegendAppearance {
    /// Slot and resolver are paired here rather than at each call site, so a caller
    /// can't resolve the header through the monospaced slot and get a plausible-
    /// looking wrong font.
    func labelNSFont(defaultSize: CGFloat) -> NSFont {
        labelFont.nsFont(slot: .proportional, defaultSize: defaultSize)
    }

    func shortcutNSFont(defaultSize: CGFloat) -> NSFont {
        shortcutFont.nsFont(slot: .monospaced, defaultSize: defaultSize)
    }

    func headerNSFont(defaultSize: CGFloat) -> NSFont {
        headerFont.nsFont(slot: .proportional, defaultSize: defaultSize)
    }
}

extension LegendAppearance {
    /// Hoisted so the no-override path hands SwiftUI the *same* box every render —
    /// `AnyShapeStyle` boxes into a class and isn't `Equatable`, so a fresh one per
    /// access makes `_ForegroundStyleModifier` compare unequal on every body pass.
    /// The shortcut/header defaults stay hierarchical (`.primary` / `.secondary`) to
    /// keep their vibrancy treatment inside the `.panel` material; the label default
    /// is deliberately a flat `Color` — 75% primary — and does not get it.
    static let defaultShortcutForeground = AnyShapeStyle(.primary)
    static let defaultLabelForeground = AnyShapeStyle(Color.primary.opacity(0.75))
    static let defaultHeaderForeground = AnyShapeStyle(.secondary)

    var shortcutForeground: AnyShapeStyle {
        shortcutColor.map(AnyShapeStyle.init) ?? Self.defaultShortcutForeground
    }

    var labelForeground: AnyShapeStyle {
        labelColor.map(AnyShapeStyle.init) ?? Self.defaultLabelForeground
    }

    var headerForeground: AnyShapeStyle {
        headerColor.map(AnyShapeStyle.init) ?? Self.defaultHeaderForeground
    }
}
