import AppKit
import Foundation
import ShortcutField
@testable import ShortcutKit
import SwiftUI
import Testing

@MainActor
@Suite("View.shortcut") struct ViewShortcutTests {
    private func isolatedStore() -> UserDefaultsStore {
        let suite = "ShortcutKitTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return UserDefaultsStore(defaults: defaults)
    }

    @Test("the modifier exists and resolves the action's current shortcut")
    func resolvesCurrentShortcut() {
        let ctx = ShortcutContext<MenuKitAct>("editor") { _, _ in }
        _ = ShortcutRegistry(contexts: [ctx], store: isolatedStore())
        #expect(ShortcutKitHelpers.resolveKeyboardEquivalent(for: .save, in: ctx) != nil)
        #expect(ShortcutKitHelpers.resolveKeyboardEquivalent(for: .openProject, in: ctx) == nil)
    }
}
