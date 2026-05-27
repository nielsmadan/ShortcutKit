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
        #expect(registry.__activeContextIDs == [])
        ctx.__activate()
        #expect(registry.__activeContextIDs == ["editor"])
    }

    @Test("deactivating removes the matcher")
    func deactivateRemovesMatcher() {
        let ctx = ShortcutContext<PlumbAction>("editor")
        let registry = ShortcutRegistry(contexts: [ctx], store: isolatedStore())
        ctx.__activate()
        ctx.__deactivate()
        #expect(registry.__activeContextIDs == [])
    }

    @Test("activating two contexts orders them by activation (innermost = last)")
    func activationOrdering() {
        let outer = ShortcutContext<PlumbAction>("outer")
        let inner = ShortcutContext<PlumbAction>("inner")
        let registry = ShortcutRegistry(contexts: [outer, inner], store: isolatedStore())
        outer.__activate()
        inner.__activate()
        #expect(registry.__activeContextIDs == ["outer", "inner"])
    }

    @Test("matcher-driven dispatch fires the action via the router")
    func endToEndMatcherDispatch() {
        var fired: (PlumbAction, ShortcutDispatch)?
        let ctx = ShortcutContext<PlumbAction>("editor")
        ctx.__setActiveHandler { action, kind in
            fired = (action, kind)
        }
        let registry = ShortcutRegistry(contexts: [ctx], store: isolatedStore())
        ctx.__activate()

        let cg = CGEvent(keyboardEventSource: nil,
                         virtualKey: CGKeyCode(kVK_ANSI_S), keyDown: true)!
        cg.flags = CGEventFlags(rawValue: UInt64(NSEvent.ModifierFlags.command.rawValue))
        let event = NSEvent(cgEvent: cg)!

        #expect(registry.__router.handle(event) == .fired)
        #expect(fired?.0 == .save)
        #expect(fired?.1 == .discrete)
    }
}
