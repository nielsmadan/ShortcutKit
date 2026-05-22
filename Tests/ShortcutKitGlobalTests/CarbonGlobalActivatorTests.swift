import Carbon.HIToolbox
import ShortcutField
@testable import ShortcutKit
@testable import ShortcutKitGlobal
import Testing

@MainActor
@Suite("CarbonGlobalActivator") struct CarbonGlobalActivatorTests {
    enum GlobalAct: String, ShortcutAction {
        case ping
        // F18 — almost never a live system hotkey.
        var definition: ShortcutActionDefinition {
            .init("Ping", Shortcut.discrete(DiscreteShortcut(keyCode: UInt16(kVK_F18), modifiers: [])))
        }
    }

    enum ChordAct: String, ShortcutAction {
        case palette
        var definition: ShortcutActionDefinition { .init("Palette", Shortcut("cmd+k cmd+p")) }
    }

    @Test("start registers a global binding and reports .registered")
    func startRegisters() throws {
        let ctx = ShortcutContext<GlobalAct>("global", scope: .global) { _, _ in }
        let registry = ShortcutRegistry(contexts: [ctx])
        let activator = CarbonGlobalActivator()
        try activator.start(registry)
        defer { activator.stop() }

        let id = BindingID(contextID: "global", actionID: "ping", bindingIndex: 0)
        let status = activator.status[id]
        if case .registered = status {} else if case .shadowedBySystem = status {} else {
            Issue.record("expected .registered or .shadowedBySystem, got \(String(describing: status))")
        }
    }

    @Test("chord in a global context reports .unsupportedTrigger")
    func chordUnsupported() throws {
        // A multi-step shortcut declared as a default in a global context is an
        // error-severity conflict (`multiStepInGlobal`). Core trips
        // `assertionFunction` for that; suppress it so the registry builds and
        // the binding reaches the activator, which reports `.unsupportedTrigger`.
        let prior = ShortcutRegistry.assertionFunction
        ShortcutRegistry.assertionFunction = { _ in }
        defer { ShortcutRegistry.assertionFunction = prior }

        let ctx = ShortcutContext<ChordAct>("global", scope: .global) { _, _ in }
        let registry = ShortcutRegistry(contexts: [ctx])
        let activator = CarbonGlobalActivator()
        try activator.start(registry)
        defer { activator.stop() }

        let id = BindingID(contextID: "global", actionID: "palette", bindingIndex: 0)
        if case .unsupportedTrigger = activator.status[id] {} else {
            Issue.record("expected .unsupportedTrigger, got \(String(describing: activator.status[id]))")
        }
    }

    @Test("double start throws .alreadyStarted")
    func doubleStartThrows() throws {
        let registry = ShortcutRegistry(contexts: [])
        let activator = CarbonGlobalActivator()
        try activator.start(registry)
        defer { activator.stop() }
        #expect(throws: GlobalActivatorError.alreadyStarted) {
            try activator.start(registry)
        }
    }

    @Test("stop clears status and allows restart")
    func stopAllowsRestart() throws {
        let registry = ShortcutRegistry(contexts: [])
        let activator = CarbonGlobalActivator()
        try activator.start(registry)
        activator.stop()
        #expect(activator.status.isEmpty)
        try activator.start(registry)
        activator.stop()
    }

    @Test("verification downgrades a system-claimed combo to .shadowedBySystem")
    func verificationDetectsShadowing() {
        let combo = CarbonHotKeyCombo(keyCode: UInt32(kVK_F18), carbonModifiers: 0)
        let systemSet: Set<CarbonHotKeyCombo> = [combo]

        let downgraded = CarbonGlobalActivator.verifiedStatus(
            current: .registered, combo: combo, systemCombos: systemSet
        )
        #expect(downgraded == .shadowedBySystem)

        let unchanged = CarbonGlobalActivator.verifiedStatus(
            current: .registered, combo: combo, systemCombos: []
        )
        #expect(unchanged == .registered)
    }

    @Test("verification leaves non-registered statuses untouched")
    func verificationIgnoresOtherStatuses() {
        let combo = CarbonHotKeyCombo(keyCode: 1, carbonModifiers: 0)
        #expect(CarbonGlobalActivator.verifiedStatus(
            current: .unsupportedTrigger, combo: combo, systemCombos: [combo]
        ) == .unsupportedTrigger)
    }

    @Test("editing a global binding re-registers via auto-sync")
    func autoSyncOnBindingChange() throws {
        let ctx = ShortcutContext<GlobalAct>("global", scope: .global) { _, _ in }
        let registry = ShortcutRegistry(contexts: [ctx])
        let activator = CarbonGlobalActivator()
        try activator.start(registry)
        defer { activator.stop() }

        let id = BindingID(contextID: "global", actionID: "ping", bindingIndex: 0)
        // F19 — another rarely-bound key.
        registry.setShortcuts(
            [Shortcut.discrete(DiscreteShortcut(keyCode: UInt16(kVK_F19), modifiers: []))],
            for: .ping, in: ctx
        )
        let status = activator.status[id]
        #expect(status == .registered || status == .shadowedBySystem)
    }
}
