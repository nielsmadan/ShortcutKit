import AppKit
import Carbon.HIToolbox

enum CarbonModifiers {
    private static let pairs: [(ns: NSEvent.ModifierFlags, carbon: Int)] = [
        (.command, cmdKey),
        (.shift, shiftKey),
        (.option, optionKey),
        (.control, controlKey),
    ]

    static func carbon(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var result: UInt32 = 0
        for pair in pairs where flags.contains(pair.ns) {
            result |= UInt32(pair.carbon)
        }
        return result
    }
}
