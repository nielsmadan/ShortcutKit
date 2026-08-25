import Foundation
@testable import ShortcutKitUI
import Testing

@MainActor
struct HintPolicyTests {
    @Test func alwaysShowsEveryTime() {
        var gate = HintPolicyGate()
        let action = ActionRef(contextID: "editor", actionID: "save")
        #expect(gate.shouldShow(action: action, policy: .always))
        gate.markShown(action: action)
        #expect(gate.shouldShow(action: action, policy: .always))
    }

    @Test func oncePerSessionShowsOnceThenSuppresses() {
        var gate = HintPolicyGate()
        let save = ActionRef(contextID: "editor", actionID: "save")
        let new = ActionRef(contextID: "editor", actionID: "new")
        #expect(gate.shouldShow(action: save, policy: .oncePerSession))
        gate.markShown(action: save)
        #expect(gate.shouldShow(action: save, policy: .oncePerSession) == false)
        #expect(gate.shouldShow(action: new, policy: .oncePerSession))
    }

    @Test func timeoutSuppressesWithinWindow() {
        let clock = MutableClock()
        var gate = HintPolicyGate(now: clock.now)
        let action = ActionRef(contextID: "editor", actionID: "save")
        gate.markShown(action: action)
        clock.advance(by: 0.05)
        #expect(gate.shouldShow(action: action, policy: .timeout(0.1)) == false)
        clock.advance(by: 0.1)
        #expect(gate.shouldShow(action: action, policy: .timeout(0.1)))
    }

    @Test func policyIsEvaluatedPerCheckOnAPersistentGate() {
        var gate = HintPolicyGate()
        let action = ActionRef(contextID: "editor", actionID: "save")
        gate.markShown(action: action)
        #expect(gate.shouldShow(action: action, policy: .oncePerSession) == false)
        #expect(gate.shouldShow(action: action, policy: .always))
    }

    @Test func equalActionIDsInDifferentContextsArePacedIndependently() {
        var gate = HintPolicyGate()
        let editorSave = ActionRef(contextID: "editor", actionID: "save")
        let documentSave = ActionRef(contextID: "document", actionID: "save")

        gate.markShown(action: editorSave)

        #expect(gate.shouldShow(action: documentSave, policy: .oncePerSession))
    }
}

private final class MutableClock: @unchecked Sendable {
    private var t: TimeInterval = 0
    func advance(by dt: TimeInterval) { t += dt }
    var now: @Sendable () -> Date { { [weak self] in Date(timeIntervalSince1970: self?.t ?? 0) } }
}
