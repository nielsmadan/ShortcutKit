import Carbon.HIToolbox
@testable import ShortcutKitGlobal
import Testing

@MainActor
@Suite("CarbonHotKeyCenter") struct CarbonHotKeyCenterTests {
    @Test("register returns a hotkey and unregister clears the table")
    func registerUnregisterLifecycle() {
        let center = CarbonHotKeyCenter.shared
        center.unregisterAll() // isolate from other tests

        // F19 (kVK_F19 = 0x50) — extremely unlikely to be a live system hotkey.
        let combo = CarbonHotKeyCombo(keyCode: UInt32(kVK_F19), carbonModifiers: 0)
        let hotKey = center.register(combo: combo, onKeyDown: {})
        #expect(hotKey != nil)
        #expect(center.registeredCount == 1)

        if let hotKey {
            center.unregister(hotKey)
        }
        #expect(center.registeredCount == 0)
    }

    @Test("unregisterAll empties the table")
    func unregisterAll() {
        let center = CarbonHotKeyCenter.shared
        center.unregisterAll()
        _ = center.register(
            combo: CarbonHotKeyCombo(keyCode: UInt32(kVK_F18), carbonModifiers: 0),
            onKeyDown: {}
        )
        #expect(center.registeredCount == 1)
        center.unregisterAll()
        #expect(center.registeredCount == 0)
    }

    @Test("mode starts normal and tracks menu open/close")
    func menuModeTransitions() {
        let center = CarbonHotKeyCenter.shared
        center.unregisterAll()
        #expect(center.mode == .normal)

        center.handleMenuTrackingChange(isOpen: true)
        #expect(center.mode == .menuOpen)

        center.handleMenuTrackingChange(isOpen: false)
        #expect(center.mode == .normal)
    }

    @Test("nested menu tracking stays menuOpen until the last menu closes")
    func nestedMenuTracking() {
        let center = CarbonHotKeyCenter.shared
        center.unregisterAll()
        center.handleMenuTrackingChange(isOpen: false) // reset depth to 0
        #expect(center.mode == .normal)

        center.handleMenuTrackingChange(isOpen: true) // menu opens
        #expect(center.mode == .menuOpen)
        center.handleMenuTrackingChange(isOpen: true) // submenu opens
        #expect(center.mode == .menuOpen)
        center.handleMenuTrackingChange(isOpen: false) // submenu closes
        #expect(center.mode == .menuOpen) // still open — parent tracking
        center.handleMenuTrackingChange(isOpen: false) // parent closes
        #expect(center.mode == .normal)
    }
}
