import AppKit
import Carbon.HIToolbox

/// Converts between `NSEvent.ModifierFlags` and Carbon hotkey modifier flags
/// (`cmdKey` / `shiftKey` / `optionKey` / `controlKey`), which is what
/// `RegisterEventHotKey` expects.
enum CarbonModifiers {
    private static let pairs: [(ns: NSEvent.ModifierFlags, carbon: Int)] = [
        (.command, cmdKey),
        (.shift, shiftKey),
        (.option, optionKey),
        (.control, controlKey),
    ]

    /// Carbon modifier mask for the four hotkey-relevant flags. Other flags
    /// (caps lock, function, etc.) are ignored.
    static func carbon(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var result: UInt32 = 0
        for pair in pairs where flags.contains(pair.ns) {
            result |= UInt32(pair.carbon)
        }
        return result
    }
}
