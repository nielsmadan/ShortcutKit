import AppKit
import Carbon.HIToolbox
import Foundation
import ShortcutField
@testable import ShortcutKit
import Testing

enum SysAct: String, ShortcutAction {
    case save, longSave, zoom
    var definition: ShortcutActionDefinition {
        switch self {
        case .save: .init("Save", "cmd+s")
        case .longSave: .init("Long Save", "cmd+k cmd+s")
        case .zoom: .init("Zoom", "cmd+pinch-out @0.5")
        }
    }
}

@MainActor
final class StubSystemShortcuts: SystemShortcutsProvider {
    var set: Set<SystemHotKey>
    init(_ set: Set<SystemHotKey> = []) { self.set = set }
    func currentSystemShortcuts() -> Set<SystemHotKey> { set }
}

@MainActor
@Suite("SystemShared") struct SystemSharedTests {
    private func isolatedStore() -> UserDefaultsStore {
        let suite = "ShortcutKitTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return UserDefaultsStore(defaults: defaults)
    }

    @Test("a single-step keyboard discrete shortcut matching the system set is flagged")
    func detectsSystemShared() {
        let stub = StubSystemShortcuts([
            .init(keyCode: UInt16(kVK_ANSI_S), modifiers: .command),
        ])
        let ctx = ShortcutContext<SysAct>("editor")
        let registry = ShortcutRegistry(
            contexts: [ctx],
            store: isolatedStore(),
            systemShortcutsProvider: stub
        )

        let systemShared = registry.conflicts.compactMap { (c: Conflict) -> Conflict? in
            if case .systemShared = c { return c } else { return nil }
        }
        #expect(systemShared.count == 1)
        #expect(systemShared[0].severity == .warning)
    }

    @Test("multi-step shortcuts are not flagged (cannot map to a single system hotkey)")
    func multiStepNotFlagged() {
        let stub = StubSystemShortcuts([
            .init(keyCode: UInt16(kVK_ANSI_S), modifiers: .command),
        ])
        let ctx = ShortcutContext<SysAct>("editor")
        let registry = ShortcutRegistry(
            contexts: [ctx],
            store: isolatedStore(),
            systemShortcutsProvider: stub
        )
        let flaggedActions = registry.conflicts.compactMap { c -> String? in
            if case let .systemShared(action) = c { action.actionID } else { nil }
        }
        #expect(flaggedActions == ["save"])
    }

    @Test("continuous shortcuts are not flagged (system hotkeys are keyboard-only)")
    func continuousNotFlagged() {
        let stub = StubSystemShortcuts([
            .init(keyCode: UInt16(kVK_ANSI_S), modifiers: .command),
        ])
        let ctx = ShortcutContext<SysAct>("editor")
        let registry = ShortcutRegistry(
            contexts: [ctx],
            store: isolatedStore(),
            systemShortcutsProvider: stub
        )
        let zoomFlags = registry.conflicts.contains { c in
            if case let .systemShared(action) = c { action.actionID == "zoom" } else { false }
        }
        #expect(zoomFlags == false)
    }
}
