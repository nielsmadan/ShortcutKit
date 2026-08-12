import AppKit
import Carbon.HIToolbox
import Foundation
import ShortcutField
@testable import ShortcutKit
import SwiftUI
import Testing

enum PlumbAction: String, ShortcutAction {
    case save
    var definition: ShortcutActionDefinition { .init("Save", "cmd+s") }
}

@MainActor
@Suite("ActivationPlumbing") struct ActivationPlumbingTests {
    private func isolatedStore() -> UserDefaultsStore {
        let suite = "ShortcutKitTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return UserDefaultsStore(defaults: defaults)
    }

    @Test("activating a context pushes its matcher onto the router")
    func activatePushesMatcher() {
        let ctx = ShortcutContext<PlumbAction>("editor")
        let registry = ShortcutRegistry(contexts: [ctx], store: isolatedStore())
        let activationID = UUID()
        #expect(registry.__activeContextIDs == [])
        ctx.__activate(activationID: activationID)
        #expect(registry.__activeContextIDs == ["editor"])
    }

    @Test("deactivating removes the matcher")
    func deactivateRemovesMatcher() {
        let ctx = ShortcutContext<PlumbAction>("editor")
        let registry = ShortcutRegistry(contexts: [ctx], store: isolatedStore())
        let activationID = UUID()
        ctx.__activate(activationID: activationID)
        ctx.__deactivate(activationID: activationID)
        #expect(registry.__activeContextIDs == [])
    }

    @Test("activating two contexts orders them by activation (innermost = last)")
    func activationOrdering() {
        let outer = ShortcutContext<PlumbAction>("outer")
        let inner = ShortcutContext<PlumbAction>("inner")
        let registry = ShortcutRegistry(contexts: [outer, inner], store: isolatedStore())
        outer.__activate(activationID: UUID())
        inner.__activate(activationID: UUID())
        #expect(registry.__activeContextIDs == ["outer", "inner"])
    }

    @Test("matcher-driven dispatch fires the action via the router")
    func endToEndMatcherDispatch() {
        var fired: (PlumbAction, ShortcutDispatch)?
        let ctx = ShortcutContext<PlumbAction>("editor")
        let activationID = UUID()
        ctx.__setActiveHandler({ action, kind in
            fired = (action, kind)
        }, for: activationID)
        let registry = ShortcutRegistry(contexts: [ctx], store: isolatedStore())
        ctx.__activate(activationID: activationID)

        let cg = CGEvent(keyboardEventSource: nil,
                         virtualKey: CGKeyCode(kVK_ANSI_S), keyDown: true)!
        cg.flags = CGEventFlags(rawValue: UInt64(NSEvent.ModifierFlags.command.rawValue))
        let event = NSEvent(cgEvent: cg)!

        #expect(registry.__router.handle(event) == .fired)
        #expect(fired?.0 == .save)
        #expect(fired?.1 == .discrete)
    }

    @Test("deactivating one mount preserves another mount of the same context")
    func deactivationIsMountScoped() {
        let context = ShortcutContext<PlumbAction>("editor")
        let registry = ShortcutRegistry(contexts: [context], store: isolatedStore())
        let first = UUID()
        let second = UUID()
        var firedBy: String?
        context.__setActiveHandler({ _, _ in firedBy = "first" }, for: first)
        context.__setActiveHandler({ _, _ in firedBy = "second" }, for: second)
        context.__activate(activationID: first)
        context.__activate(activationID: second)

        context.__deactivate(activationID: first)
        context.__clearActiveHandler(for: first)
        registry.dispatch(contextID: "editor", actionID: "save")

        #expect(registry.__activeContextIDs == ["editor"])
        #expect(firedBy == "second")
    }

    @Test("deactivating the newest mount restores routing to the older mount")
    func newestDeactivationRestoresOlderMount() {
        let context = ShortcutContext<PlumbAction>("editor")
        let registry = ShortcutRegistry(contexts: [context], store: isolatedStore())
        let first = UUID()
        let second = UUID()
        var firedBy: String?
        context.__setActiveHandler({ _, _ in firedBy = "first" }, for: first)
        context.__setActiveHandler({ _, _ in firedBy = "second" }, for: second)
        context.__activate(activationID: first)
        context.__activate(activationID: second)

        context.__deactivate(activationID: second)
        context.__clearActiveHandler(for: second)
        #expect(registry.__router.handle(keyDown(keyCode: kVK_ANSI_S, modifiers: .command)) == .fired)

        #expect(firedBy == "first")
    }

    @Test("reload rebuilds active matcher instances")
    func reloadRebuildsActiveMatchers() throws {
        let store = isolatedStore()
        let context = ShortcutContext<PlumbAction>("editor")
        let registry = ShortcutRegistry(contexts: [context], store: store)
        let activationID = UUID()
        var fired = false
        context.__setActiveHandler({ _, _ in fired = true }, for: activationID)
        context.__activate(activationID: activationID)
        try store.save(RawState(overrides: ["editor": ["save": ["cmd+shift+s"]]]))

        #expect(registry.reload())
        #expect(registry.__router.handle(keyDown(
            keyCode: kVK_ANSI_S,
            modifiers: [.command, .shift]
        )) == .fired)

        #expect(fired)
    }

    private func keyDown(keyCode: Int, modifiers: NSEvent.ModifierFlags) -> NSEvent {
        let event = CGEvent(
            keyboardEventSource: nil,
            virtualKey: CGKeyCode(keyCode),
            keyDown: true
        )!
        event.flags = CGEventFlags(rawValue: UInt64(modifiers.rawValue))
        return NSEvent(cgEvent: event)!
    }
}
