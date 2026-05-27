@testable import ShortcutKit
import Testing

@MainActor
struct ContextScopeTests {
    enum NoopAction: String, ShortcutAction {
        case noop
        var definition: ShortcutActionDefinition { .init("Noop") }
    }

    @Test func defaultScopeIsLocal() {
        let ctx = ShortcutContext<NoopAction>("ctx")
        #expect(ctx.scope == .local)
        #expect(ctx.includeInSettings == true)
    }

    @Test func globalScopeOptIn() {
        let ctx = ShortcutContext<NoopAction>(global: "ctx") { _, _ in }
        #expect(ctx.scope == .global)
    }

    @Test func includeInSettingsIsMutableOnConcreteType() {
        let ctx = ShortcutContext<NoopAction>("ctx")
        #expect(ctx.includeInSettings == true)
        ctx.includeInSettings = false
        #expect(ctx.includeInSettings == false)
    }
}
