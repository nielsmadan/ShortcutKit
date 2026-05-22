import AppKit
import Carbon.HIToolbox
import Foundation
import ShortcutField
@testable import ShortcutKit
import Testing

enum MenuAct: String, ShortcutAction {
    case save
    var definition: ShortcutActionDefinition { .init("Save", "cmd+s") }
}

@MainActor
@Suite("MenuCollisions") struct MenuCollisionsTests {
    private func isolatedStore() -> UserDefaultsStore {
        let suite = "ShortcutKitTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return UserDefaultsStore(defaults: defaults)
    }

    private func buildMenu(title: String, keyEquivalent: String, modifiers: NSEvent.ModifierFlags) -> NSMenu {
        let menu = NSMenu(title: "Main")
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: keyEquivalent)
        item.keyEquivalentModifierMask = modifiers
        menu.addItem(item)
        return menu
    }

    @Test("a single-step keyboard binding colliding with a menu item is reported")
    func detectsMenuCollision() {
        let ctx = ShortcutContext<MenuAct>("editor") { _, _ in }
        let registry = ShortcutRegistry(contexts: [ctx], store: isolatedStore())
        let menu = buildMenu(title: "File…", keyEquivalent: "s", modifiers: .command)
        let collisions = registry.menuCollisions(in: menu)
        #expect(collisions.count == 1)
        if case let .menuCollision(_, action, menuItemTitle) = collisions[0] {
            #expect(action.actionID == "save")
            #expect(menuItemTitle == "File…")
        } else { Issue.record("expected .menuCollision") }
    }

    @Test("a non-colliding menu item is not reported")
    func nonCollidingIgnored() {
        let ctx = ShortcutContext<MenuAct>("editor") { _, _ in }
        let registry = ShortcutRegistry(contexts: [ctx], store: isolatedStore())
        let menu = buildMenu(title: "Quit", keyEquivalent: "q", modifiers: .command)
        #expect(registry.menuCollisions(in: menu).isEmpty)
    }

    @Test("nested submenus are walked")
    func walksSubmenus() {
        let ctx = ShortcutContext<MenuAct>("editor") { _, _ in }
        let registry = ShortcutRegistry(contexts: [ctx], store: isolatedStore())
        let parent = NSMenu(title: "Main")
        let parentItem = NSMenuItem(title: "File", action: nil, keyEquivalent: "")
        let sub = NSMenu(title: "File")
        let leaf = NSMenuItem(title: "Save", action: nil, keyEquivalent: "s")
        leaf.keyEquivalentModifierMask = .command
        sub.addItem(leaf)
        parentItem.submenu = sub
        parent.addItem(parentItem)
        let collisions = registry.menuCollisions(in: parent)
        #expect(collisions.count == 1)
    }
}
