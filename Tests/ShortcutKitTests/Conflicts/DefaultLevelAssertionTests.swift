import Foundation
import ShortcutField
@testable import ShortcutKit
import Testing

enum BuggyAct: String, ShortcutAction {
    case save, alsoSave
    var definition: ShortcutActionDefinition {
        // BUG: two defaults bound to cmd+s — same context → .error severity.
        switch self {
        case .save: .init("Save", "cmd+s")
        case .alsoSave: .init("Also Save", "cmd+s")
        }
    }
}

@MainActor
@Suite("DefaultLevelAssertion") struct DefaultLevelAssertionTests {
    private func isolatedStore() -> UserDefaultsStore {
        let suite = "ShortcutKitTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return UserDefaultsStore(defaults: defaults)
    }

    @Test("an error-severity conflict purely from defaults trips assertionFunction")
    func defaultLevelErrorTripsAssertion() {
        var captured: String?
        let prior = ShortcutRegistry.assertionFunction
        ShortcutRegistry.assertionFunction = { captured = $0 }
        defer { ShortcutRegistry.assertionFunction = prior }

        let ctx = ShortcutContext<BuggyAct>("editor") { _, _ in }
        _ = ShortcutRegistry(contexts: [ctx], store: isolatedStore())

        #expect(captured?.contains("default-level") == true)
        #expect(captured?.contains("editor.save") == true)
        #expect(captured?.contains("editor.alsoSave") == true)
    }
}
