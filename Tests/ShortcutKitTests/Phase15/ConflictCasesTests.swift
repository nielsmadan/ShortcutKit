import ShortcutField
@testable import ShortcutKit
import Testing

@MainActor
struct ConflictCasesTests {
    enum LocalA: String, ShortcutAction {
        case save
        var definition: ShortcutActionDefinition { .init("Save", "cmd+s") }
    }

    enum GlobalA: String, ShortcutAction {
        case quickOpen
        var definition: ShortcutActionDefinition { .init("Open", "cmd+s") }
    }

    @Test func crossScopeIsShadowedByGlobal() {
        let prior = ShortcutRegistry.assertionFunction
        ShortcutRegistry.assertionFunction = { _ in }
        defer { ShortcutRegistry.assertionFunction = prior }
        let local = ShortcutContext<LocalA>("editor")
        let global = ShortcutContext<GlobalA>(global: "launcher") { _, _ in }
        let reg = ShortcutRegistry(contexts: [local, global])
        let conflicts = reg.conflicts
        #expect(conflicts.contains { if case .shadowedByGlobal = $0 { true } else { false } })
    }

    @Test func multiStepGlobalIsUnsupportedInScope() {
        enum Chord: String, ShortcutAction {
            case openPalette
            var definition: ShortcutActionDefinition {
                .init("Palette", "cmd+k cmd+p")
            }
        }
        let prior = ShortcutRegistry.assertionFunction
        ShortcutRegistry.assertionFunction = { _ in }
        defer { ShortcutRegistry.assertionFunction = prior }
        let ctx = ShortcutContext<Chord>(global: "g") { _, _ in }
        let reg = ShortcutRegistry(contexts: [ctx])
        #expect(reg.conflicts.contains { if case .unsupportedInScope = $0 { true } else { false } })
    }

    @Test func perBindingOccurrenceForArrayOverrides() {
        enum Dup: String, ShortcutAction, CaseIterable {
            case a, b
            var definition: ShortcutActionDefinition {
                switch self {
                case .a: .init("A", defaults: [Shortcut("cmd+s"), Shortcut("ctrl+s")])
                case .b: .init("B", "ctrl+s")
                }
            }
        }
        let prior = ShortcutRegistry.assertionFunction
        ShortcutRegistry.assertionFunction = { _ in }
        defer { ShortcutRegistry.assertionFunction = prior }
        let ctx = ShortcutContext<Dup>("x")
        let reg = ShortcutRegistry(contexts: [ctx])
        let dups = reg.conflicts.compactMap { c -> [Occurrence]? in
            if case let .duplicate(o) = c { return o } else { return nil }
        }
        // ctrl+s collides across .a (second binding) and .b → 2 occurrences in one duplicate
        #expect(dups.first?.count == 2)
    }
}
