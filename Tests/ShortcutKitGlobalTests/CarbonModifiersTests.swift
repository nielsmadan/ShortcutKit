import AppKit
import Carbon.HIToolbox
@testable import ShortcutKitGlobal
import Testing

@Suite("CarbonModifiers") struct CarbonModifiersTests {
    @Test("each flag maps to its Carbon constant")
    func individualFlags() {
        #expect(CarbonModifiers.carbon(from: .command) == UInt32(cmdKey))
        #expect(CarbonModifiers.carbon(from: .shift) == UInt32(shiftKey))
        #expect(CarbonModifiers.carbon(from: .option) == UInt32(optionKey))
        #expect(CarbonModifiers.carbon(from: .control) == UInt32(controlKey))
    }

    @Test("combined flags OR together")
    func combinedFlags() {
        let combined: NSEvent.ModifierFlags = [.command, .shift]
        #expect(CarbonModifiers.carbon(from: combined) == UInt32(cmdKey) | UInt32(shiftKey))
    }

    @Test("non-modifier flags are ignored")
    func ignoresNoise() {
        let noisy: NSEvent.ModifierFlags = [.command, .capsLock, .function]
        #expect(CarbonModifiers.carbon(from: noisy) == UInt32(cmdKey))
    }
}
