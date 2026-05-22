import ShortcutField
import ShortcutKit
@testable import ShortcutKitUI
import Testing

@MainActor
struct ScopePolicyTests {
    @Test func rejectsMultiStepInGlobalScope() {
        let result = ScopePolicy.global.validate(Shortcut("cmd+k cmd+p"))
        #expect(result == .reject(reason: .multiStepInGlobal))
    }

    @Test func acceptsSingleStepInGlobalScope() {
        #expect(ScopePolicy.global.validate(Shortcut("cmd+s")) == .accept)
    }

    @Test func localScopeAcceptsChords() {
        #expect(ScopePolicy.local.validate(Shortcut("cmd+k cmd+p")) == .accept)
    }

    @Test func bridgesContextScope() {
        #expect(ScopePolicy(.local) == .local)
        #expect(ScopePolicy(.global) == .global)
    }

    @Test func rejectsContinuousInGlobalScope() {
        let cont: Shortcut = .continuous(.init(
            kind: .scroll(direction: .up),
            modifiers: .command,
            sensitivity: 0.5
        ))
        #expect(ScopePolicy.global.validate(cont) == .reject(reason: .continuousInGlobal))
    }
}
