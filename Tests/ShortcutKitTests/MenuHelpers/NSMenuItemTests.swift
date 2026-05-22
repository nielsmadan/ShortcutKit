import AppKit
import Carbon.HIToolbox
import Combine
import Foundation
import ShortcutField
@testable import ShortcutKit
import Testing

enum MenuKitAct: String, ShortcutAction {
    case save, openProject
    var definition: ShortcutActionDefinition {
        switch self {
        case .save: .init("Save", "cmd+s")
        case .openProject: .init("Open Project", "cmd+k cmd+o")
        }
    }
}

@MainActor
@Suite("NSMenuItem.shortcutKitItem") struct NSMenuItemShortcutKitTests {
    private func isolatedStore() -> UserDefaultsStore {
        let suite = "ShortcutKitTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return UserDefaultsStore(defaults: defaults)
    }

    @Test("single-step keyboard binding sets keyEquivalent and modifier mask")
    func singleStepKeyboardSetsKeyEquivalent() {
        let ctx = ShortcutContext<MenuKitAct>("editor") { _, _ in }
        _ = ShortcutRegistry(contexts: [ctx], store: isolatedStore())
        let item = NSMenuItem.shortcutKitItem(.save, in: ctx)
        #expect(item.title == "Save")
        #expect(item.keyEquivalent == "s")
        #expect(item.keyEquivalentModifierMask == .command)
    }

    @Test("multi-step binding leaves keyEquivalent empty")
    func multiStepNoKeyEquivalent() {
        let ctx = ShortcutContext<MenuKitAct>("editor") { _, _ in }
        _ = ShortcutRegistry(contexts: [ctx], store: isolatedStore())
        let item = NSMenuItem.shortcutKitItem(.openProject, in: ctx)
        #expect(item.keyEquivalent.isEmpty)
    }

    @Test("clicking the item dispatches the action")
    func clickDispatchesAction() {
        var fired = false
        let ctx = ShortcutContext<MenuKitAct>("editor") { action, _ in
            if action == .save { fired = true }
        }
        _ = ShortcutRegistry(contexts: [ctx], store: isolatedStore())
        let item = NSMenuItem.shortcutKitItem(.save, in: ctx)
        _ = item.target?.perform(item.action, with: item)
        #expect(fired)
    }

    @Test("setOverride re-reads keyEquivalent")
    func reReadsOnOverride() {
        let ctx = ShortcutContext<MenuKitAct>("editor") { _, _ in }
        let registry = ShortcutRegistry(contexts: [ctx], store: isolatedStore())
        let item = NSMenuItem.shortcutKitItem(.save, in: ctx)
        #expect(item.keyEquivalent == "s")
        registry.setOverride(contextID: "editor", actionID: "save", shortcut: "cmd+shift+t")
        #expect(item.keyEquivalent == "t")
        #expect(item.keyEquivalentModifierMask.contains(.shift))
    }

    @Test("custom title overrides the action's displayName")
    func customTitle() {
        let ctx = ShortcutContext<MenuKitAct>("editor") { _, _ in }
        _ = ShortcutRegistry(contexts: [ctx], store: isolatedStore())
        let item = NSMenuItem.shortcutKitItem(.save, in: ctx, title: "Save File…")
        #expect(item.title == "Save File…")
    }
}
