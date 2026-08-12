import AppKit
import SwiftUI

/// Menlo distinguishes ambiguous characters and contains the legend's key glyphs.
let legendDefaultShortcutFontName = "Menlo"

/// One font slot in the legend.
///
/// `nil` fields inherit the slot's built-in value, so options can be overridden independently:
/// ```swift
/// LegendFont(face: .named("Inter"))
/// ```
public struct LegendFont: Sendable, Hashable {
    /// Typeface used by the slot.
    public enum Face: Sendable, Hashable {
        /// The proportional system font; shortcut glyphs will not align between rows.
        case system(weight: NSFont.Weight = .regular)
        /// The system monospace font; unsupported key glyphs may use fallback fonts.
        case monospacedSystem(weight: NSFont.Weight = .regular)
        /// A PostScript or family name. Missing fonts fall back to the slot default.
        case named(String)
    }

    /// `nil` (the default) keeps the slot's built-in face — the system font for the
    /// label and header, `Menlo` for the shortcut column.
    public var face: Face?

    /// Point size. `nil` inherits ``LegendSize``; invalid values are stored as `nil`.
    /// Explicit sizes scale column widths proportionally.
    public var size: CGFloat? {
        get { rawSize }
        set { rawSize = Self.sanitized(newValue) }
    }

    private var rawSize: CGFloat?

    public init(face: Face? = nil, size: CGFloat? = nil) {
        self.face = face
        rawSize = Self.sanitized(size)
    }

    private static func sanitized(_ size: CGFloat?) -> CGFloat? {
        guard let size, size.isFinite, size > 0 else { return nil }
        return size
    }

    /// The built-in font for this slot.
    public static let `default` = LegendFont()
}

extension LegendFont {
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

/// Fonts and colors for ``KeyBindingsLegendView``.
///
/// Fields inherit the built-in appearance. The legend does not use Dynamic Type;
/// resize it with ``LegendSize`` or ``LegendFont/size``.
public struct LegendAppearance: Sendable, Hashable {
    /// Entry label — the action's name. Pairs with ``labelColor``.
    public var labelFont: LegendFont
    /// Shortcut column, monospaced by default.
    public var shortcutFont: LegendFont
    /// Group headers.
    public var headerFont: LegendFont
    /// Shortcut color. `nil` preserves the built-in hierarchical style.
    public var shortcutColor: Color?
    /// Label color. `nil` preserves the built-in style.
    public var labelColor: Color?
    /// Header color. `nil` preserves the built-in hierarchical style.
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
    // Reuse the boxed defaults so SwiftUI sees stable style identities across renders.
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
