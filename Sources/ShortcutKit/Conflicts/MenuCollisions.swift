import AppKit
import ShortcutField

/// Walks an `NSMenu` tree collecting `(keyCode, modifiers)` → title pairs for
/// every item with a non-empty `keyEquivalent`. Used by `menuCollisions(in:)`.
///
/// `NSMenuItem.keyEquivalent` is a character; mapping it to a virtual keycode
/// uses a built-in character-to-keycode table covering ANSI letters, digits,
/// and standard punctuation — the realistic 99% of menu shortcuts. Anything
/// outside the table is silently skipped — the worst case is a false negative.
@MainActor
enum MenuShortcutWalker {
    static func shortcuts(in menu: NSMenu) -> [SystemHotKey: String] {
        var result: [SystemHotKey: String] = [:]
        collect(from: menu, into: &result)
        return result
    }

    private static func collect(from menu: NSMenu, into result: inout [SystemHotKey: String]) {
        for item in menu.items {
            if !item.keyEquivalent.isEmpty, let key = hotKey(for: item) {
                result[key] = item.title
            }
            if let submenu = item.submenu {
                collect(from: submenu, into: &result)
            }
        }
    }

    private static func hotKey(for item: NSMenuItem) -> SystemHotKey? {
        guard let code = keyCode(for: item.keyEquivalent) else { return nil }
        return SystemHotKey(
            keyCode: code,
            modifiers: canonicalize(item.keyEquivalentModifierMask)
        )
    }

    private static func canonicalize(_ mask: NSEvent.ModifierFlags) -> NSEvent.ModifierFlags {
        var out: NSEvent.ModifierFlags = []
        if mask.contains(.command) { out.insert(.command) }
        if mask.contains(.shift) { out.insert(.shift) }
        if mask.contains(.option) { out.insert(.option) }
        if mask.contains(.control) { out.insert(.control) }
        return out
    }

    private static func keyCode(for character: String) -> UInt16? {
        MenuKeyMapping.keyCode(for: character)
    }
}
