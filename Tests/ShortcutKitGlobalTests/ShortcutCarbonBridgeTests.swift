import AppKit
import Carbon.HIToolbox
import ShortcutField
@testable import ShortcutKitGlobal
import Testing

@Suite("ShortcutCarbonBridge") struct ShortcutCarbonBridgeTests {
    @Test("single-step key shortcut maps to a Carbon combo")
    func singleKeyShortcut() {
        let combo = ShortcutCarbonBridge.combo(for: Shortcut("ctrl+opt+cmd+k"))
        #expect(combo != nil)
        #expect(combo?.keyCode == UInt32(kVK_ANSI_K))
        #expect(combo?.carbonModifiers
            == UInt32(controlKey) | UInt32(optionKey) | UInt32(cmdKey))
    }

    @Test("multi-step chord is unrepresentable")
    func chordIsNil() {
        #expect(ShortcutCarbonBridge.combo(for: Shortcut("cmd+k cmd+p")) == nil)
    }

    @Test("continuous shortcut is unrepresentable")
    func continuousIsNil() {
        let continuous = Shortcut.continuous(
            .init(kind: .rotateClockwise, modifiers: [], sensitivity: 0.5)
        )
        #expect(ShortcutCarbonBridge.combo(for: continuous) == nil)
    }
}
