import AppKit
import Carbon.HIToolbox
import ShortcutField

/// An enabled macOS symbolic hotkey.
///
/// `Hashable` is written by hand because `NSEvent.ModifierFlags` conforms to
/// `OptionSet` + `Equatable` but not `Hashable`, so synthesis can't derive it.
public struct SystemHotKey: Hashable, Sendable {
    public let keyCode: UInt16
    public let modifiers: NSEvent.ModifierFlags

    public init(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(keyCode)
        hasher.combine(modifiers.rawValue)
    }

    public static func == (lhs: SystemHotKey, rhs: SystemHotKey) -> Bool {
        lhs.keyCode == rhs.keyCode && lhs.modifiers == rhs.modifiers
    }
}

public extension SystemHotKey {
    /// Creates an entry from a single-key discrete shortcut.
    ///
    /// Returns `nil` for continuous, multi-step, or non-key shortcuts.
    init?(_ shortcut: Shortcut) {
        guard case let .discrete(discrete) = shortcut,
              discrete.steps.count == 1,
              let step = discrete.steps.first,
              case let .key(keyCode) = step.kind
        else { return nil }
        self.init(keyCode: UInt16(keyCode), modifiers: step.modifiers)
    }
}

/// Provides the current set of macOS symbolic hotkeys.
@MainActor
public protocol SystemShortcutsProvider {
    func currentSystemShortcuts() -> Set<SystemHotKey>
}

/// Default provider: reads enabled symbolic hotkeys via Carbon's
/// `CopySymbolicHotKeys()`. Covers the System Settings ▸ Keyboard Shortcuts
/// set only; not app-specific or third-party global hotkeys.
@MainActor
public final class CarbonSystemShortcuts: SystemShortcutsProvider {
    public init() {}

    public func currentSystemShortcuts() -> Set<SystemHotKey> {
        var result: Set<SystemHotKey> = []
        var hotKeyArray: Unmanaged<CFArray>?
        let status = CopySymbolicHotKeys(&hotKeyArray)
        guard status == noErr, let array = hotKeyArray?.takeRetainedValue()
            as? [[String: Any]] else { return [] }
        for entry in array {
            guard let enabled = entry[kHISymbolicHotKeyEnabled as String] as? Bool, enabled,
                  let code = entry[kHISymbolicHotKeyCode as String] as? Int,
                  let mods = entry[kHISymbolicHotKeyModifiers as String] as? Int
            else { continue }
            // Carbon reports some enabled but unassigned entries with no modifiers.
            let flags = Self.nsModifiers(fromCarbon: UInt32(mods))
            guard !flags.isEmpty else { continue }
            result.insert(.init(keyCode: UInt16(code), modifiers: flags))
        }
        return result
    }

    private static func nsModifiers(fromCarbon mask: UInt32) -> NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if mask & UInt32(cmdKey) != 0 { flags.insert(.command) }
        if mask & UInt32(shiftKey) != 0 { flags.insert(.shift) }
        if mask & UInt32(optionKey) != 0 { flags.insert(.option) }
        if mask & UInt32(controlKey) != 0 { flags.insert(.control) }
        return flags
    }
}
