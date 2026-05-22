import AppKit
import Carbon.HIToolbox
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

    /// Character → virtual keycode for the common menu set. Lookup table
    /// avoids a 40-case `switch` (which trips `cyclomatic_complexity`).
    private static let characterToKeyCode: [String: UInt16] = {
        let pairs: [(String, Int)] = [
            ("a", kVK_ANSI_A), ("b", kVK_ANSI_B), ("c", kVK_ANSI_C), ("d", kVK_ANSI_D),
            ("e", kVK_ANSI_E), ("f", kVK_ANSI_F), ("g", kVK_ANSI_G), ("h", kVK_ANSI_H),
            ("i", kVK_ANSI_I), ("j", kVK_ANSI_J), ("k", kVK_ANSI_K), ("l", kVK_ANSI_L),
            ("m", kVK_ANSI_M), ("n", kVK_ANSI_N), ("o", kVK_ANSI_O), ("p", kVK_ANSI_P),
            ("q", kVK_ANSI_Q), ("r", kVK_ANSI_R), ("s", kVK_ANSI_S), ("t", kVK_ANSI_T),
            ("u", kVK_ANSI_U), ("v", kVK_ANSI_V), ("w", kVK_ANSI_W), ("x", kVK_ANSI_X),
            ("y", kVK_ANSI_Y), ("z", kVK_ANSI_Z),
            ("0", kVK_ANSI_0), ("1", kVK_ANSI_1), ("2", kVK_ANSI_2), ("3", kVK_ANSI_3),
            ("4", kVK_ANSI_4), ("5", kVK_ANSI_5), ("6", kVK_ANSI_6), ("7", kVK_ANSI_7),
            ("8", kVK_ANSI_8), ("9", kVK_ANSI_9),
            (",", kVK_ANSI_Comma), (".", kVK_ANSI_Period),
            ("/", kVK_ANSI_Slash), (";", kVK_ANSI_Semicolon),
            ("'", kVK_ANSI_Quote), ("[", kVK_ANSI_LeftBracket),
            ("]", kVK_ANSI_RightBracket), ("\\", kVK_ANSI_Backslash),
            ("-", kVK_ANSI_Minus), ("=", kVK_ANSI_Equal),
            ("`", kVK_ANSI_Grave),
        ]
        return Dictionary(uniqueKeysWithValues: pairs.map { ($0.0, UInt16($0.1)) })
    }()

    private static func keyCode(for character: String) -> UInt16? {
        characterToKeyCode[character.lowercased()]
    }
}
