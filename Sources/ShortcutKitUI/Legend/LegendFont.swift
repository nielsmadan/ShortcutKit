import AppKit
import SwiftUI

/// Menlo, not the system monospace: it slashes `0` and tails lowercase `l`, so
/// `0`/`O` and `l`/`I` stay apart in a key legend, and it's the only macOS-bundled
/// monospace with real ⌘⇧⌥⌃⌫⏎↩⇥ glyphs — the others fall back per-glyph and break
/// the advance grid.
let legendShortcutFontName = "Menlo"

func legendShortcutFont(size: CGFloat) -> Font {
    .custom(legendShortcutFontName, size: size)
}

/// Halfway between `.primary` (the shortcut) and `.secondary` (~0.5): the entry
/// label stays the quieter half of the pair without dimming to caption grey.
let legendLabelForeground = Color.primary.opacity(0.75)

func legendShortcutNSFont(size: CGFloat) -> NSFont {
    NSFont(name: legendShortcutFontName, size: size)
        ?? .monospacedSystemFont(ofSize: size, weight: .regular)
}
