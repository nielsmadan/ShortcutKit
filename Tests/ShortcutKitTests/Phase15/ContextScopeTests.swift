@testable import ShortcutKit
import Testing

@MainActor
struct ContextScopeTests {
    enum NoopAction: String, ShortcutAction {
        case noop
        var definition: ShortcutActionDefinition { .init("Noop") }
    }

    @Test func defaultScopeIsLocal() {
        let ctx = ShortcutContext<NoopAction>("ctx") { _, _ in }
        #expect(ctx.scope == .local)
        #expect(ctx.includeInSettings == true)
    }

    @Test func globalScopeOptIn() {
        let ctx = ShortcutContext<NoopAction>("ctx", scope: .global) { _, _ in }
        #expect(ctx.scope == .global)
    }

    @Test func registryBindingsPerActionDefaultIsOne() {
        let registry = ShortcutRegistry(contexts: [])
        #expect(registry.bindingsPerAction == .one)
    }

    @Test func includeInSettingsIsMutableOnConcreteType() {
        let ctx = ShortcutContext<NoopAction>("ctx") { _, _ in }
        #expect(ctx.includeInSettings == true)
        ctx.includeInSettings = false
        #expect(ctx.includeInSettings == false)
    }
}
