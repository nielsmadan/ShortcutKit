import AppKit
import Carbon.HIToolbox
import Combine
import Foundation
@testable import ShortcutField
@testable import ShortcutKit
import Testing

enum DebugAction: String, ShortcutAction {
    case save, chord, deleteItem

    var definition: ShortcutActionDefinition {
        switch self {
        case .save: .init("Save", "cmd+s")
        case .chord: .init("Chord", "cmd+k cmd+o")
        case .deleteItem: .init("Delete", "cmd+d", allowsKeyRepeat: false)
        }
    }
}

@MainActor
@Suite("Debug events") struct DebugEventTests {
    private func isolatedStore() -> UserDefaultsStore {
        let suite = "ShortcutKitTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return UserDefaultsStore(defaults: defaults)
    }

    private func keyDown(
        _ keyCode: Int,
        _ modifiers: NSEvent.ModifierFlags = .command,
        isARepeat: Bool = false
    ) -> NSEvent {
        let cg = CGEvent(keyboardEventSource: nil,
                         virtualKey: CGKeyCode(keyCode), keyDown: true)!
        cg.flags = CGEventFlags(rawValue: UInt64(modifiers.rawValue))
        cg.setIntegerValueField(.keyboardEventAutorepeat, value: isARepeat ? 1 : 0)
        return NSEvent(cgEvent: cg)!
    }

    /// Returns the events the registry emitted while `body` fed the router.
    private func recorded(
        _ body: (ShortcutContext<DebugAction>, RegistryEventRouter) -> Void
    ) -> [ShortcutDebugEvent] {
        let ctx = ShortcutContext<DebugAction>("editor")
        ctx.__setActiveHandler { _, _ in }
        let registry = ShortcutRegistry(contexts: [ctx], store: isolatedStore())
        var received: [ShortcutDebugEvent] = []
        var bag: Set<AnyCancellable> = []
        registry.debugEvents.sink { received.append($0) }.store(in: &bag)
        registry.isDebugRecording = true
        ctx.__activate(activationID: UUID())
        body(ctx, registry.router)
        return received
    }

    @Test("a fired shortcut reports the action and its stack depth")
    func firedReportsActionAndDepth() {
        let events = recorded { _, router in
            _ = router.handle(keyDown(kVK_ANSI_S))
        }

        #expect(events.count == 1)
        guard case let .dispatched(ref, depth) = events.first?.outcome else {
            Issue.record("expected .dispatched, got \(String(describing: events.first?.outcome))")
            return
        }
        #expect(ref == ActionRef(contextID: "editor", actionID: "save"))
        #expect(depth == 0)
        #expect(events[0].pressed.displayString == "⌘s")
    }

    @Test("an unbound key reports noMatch")
    func unboundReportsNoMatch() {
        let events = recorded { _, router in
            _ = router.handle(keyDown(kVK_ANSI_X))
        }

        #expect(events.map(\.outcome) == [.noMatch])
    }

    @Test("a chord's first step reports advanced")
    func chordFirstStepReportsAdvanced() {
        let events = recorded { _, router in
            _ = router.handle(keyDown(kVK_ANSI_K))
        }

        #expect(events.map(\.outcome) == [.advanced(ActionRef(contextID: "editor", actionID: "chord"))])
    }

    @Test("a suppressed key repeat is reported as such, not as dispatched")
    func repeatReportsSuppression() {
        let events = recorded { _, router in
            _ = router.handle(keyDown(kVK_ANSI_D))
            _ = router.handle(keyDown(kVK_ANSI_D, .command, isARepeat: true))
        }

        let ref = ActionRef(contextID: "editor", actionID: "deleteItem")
        #expect(events.map(\.outcome) == [.dispatched(ref, stackDepth: 0), .suppressedKeyRepeat(ref)])
    }

    @Test("nothing is emitted while recording is off")
    func silentWhenNotRecording() {
        let ctx = ShortcutContext<DebugAction>("editor")
        ctx.__setActiveHandler { _, _ in }
        let registry = ShortcutRegistry(contexts: [ctx], store: isolatedStore())
        var received: [ShortcutDebugEvent] = []
        var bag: Set<AnyCancellable> = []
        registry.debugEvents.sink { received.append($0) }.store(in: &bag)
        ctx.__activate(activationID: UUID())

        // Default is off; subscribing must not be enough to start emission.
        _ = registry.router.handle(keyDown(kVK_ANSI_S))
        #expect(received.isEmpty)

        registry.isDebugRecording = true
        _ = registry.router.handle(keyDown(kVK_ANSI_S))
        #expect(received.count == 1)

        registry.isDebugRecording = false
        _ = registry.router.handle(keyDown(kVK_ANSI_S))
        #expect(received.count == 1)
    }

    /// ShortcutField's focus gate returns `.ignored`, indistinguishable from a
    /// non-match. Pinned deliberately: if ShortcutField ever enriches its result,
    /// this test fails and we can report the real reason.
    @Test("a focus-gated keystroke is reported as noMatch")
    func focusGatedReportsNoMatch() {
        let textView = NSTextView(frame: .zero)
        textView.isEditable = true
        TextInputFocus.responderOverride = { textView }
        defer { TextInputFocus.responderOverride = nil }

        let events = recorded { _, router in
            _ = router.handle(keyDown(kVK_ANSI_S, []))
        }

        #expect(events.map(\.outcome) == [.noMatch])
    }
}

@MainActor
@Suite("Debugging doc examples") struct DebuggingDocExampleTests {
    private func isolatedStore() -> UserDefaultsStore {
        let suite = "ShortcutKitTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return UserDefaultsStore(defaults: defaults)
    }

    /// Mirrors the snippets in `ShortcutKit.docc/Debugging.md`. Keeps them
    /// compiling as the API moves.
    @Test func test_DocExample_debuggingShortcuts() {
        let ctx = ShortcutContext<DebugAction>("editor")
        ctx.__setActiveHandler { _, _ in }
        let registry = ShortcutRegistry(contexts: [ctx], store: isolatedStore())
        ctx.__activate(activationID: UUID())
        var cancellables: Set<AnyCancellable> = []
        var lines: [String] = []

        for entry in registry.activationSnapshot.innermostFirst {
            lines.append("\(entry.contextID) \(entry.activationID)")
        }

        registry.isDebugRecording = true
        registry.debugEvents
            .sink { event in
                switch event.outcome {
                case let .dispatched(ref, depth):
                    lines.append("\(event.pressed.displayString) → \(ref.actionID) at depth \(depth)")
                case let .advanced(ref):
                    lines.append("chord in progress: \(ref.actionID)")
                case let .suppressedKeyRepeat(ref):
                    lines.append("repeat suppressed: \(ref.actionID)")
                case .noMatch:
                    lines.append("nothing matched \(event.pressed.displayString)")
                }
            }
            .store(in: &cancellables)

        let cg = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_ANSI_S), keyDown: true)!
        cg.flags = CGEventFlags(rawValue: UInt64(NSEvent.ModifierFlags.command.rawValue))
        _ = registry.router.handle(NSEvent(cgEvent: cg)!)

        #expect(lines == ["editor \(registry.activationSnapshot.entries[0].activationID)",
                          "⌘s → save at depth 0"])
    }
}
