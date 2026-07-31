import Foundation
@testable import ShortcutKitUI
import Testing

@MainActor
struct HintPolicyTests {
    @Test func alwaysShowsEveryTime() {
        var gate = HintPolicyGate()
        #expect(gate.shouldShow(actionID: "save", policy: .always))
        gate.markShown(actionID: "save")
        #expect(gate.shouldShow(actionID: "save", policy: .always))
    }

    @Test func oncePerSessionShowsOnceThenSuppresses() {
        var gate = HintPolicyGate()
        #expect(gate.shouldShow(actionID: "save", policy: .oncePerSession))
        gate.markShown(actionID: "save")
        #expect(gate.shouldShow(actionID: "save", policy: .oncePerSession) == false)
        // Different action: not yet shown.
        #expect(gate.shouldShow(actionID: "new", policy: .oncePerSession))
    }

    @Test func timeoutSuppressesWithinWindow() {
        let clock = MutableClock()
        var gate = HintPolicyGate(now: clock.now)
        gate.markShown(actionID: "save")
        clock.advance(by: 0.05)
        #expect(gate.shouldShow(actionID: "save", policy: .timeout(0.1)) == false)
        clock.advance(by: 0.1)
        #expect(gate.shouldShow(actionID: "save", policy: .timeout(0.1)))
    }

    // The policy is passed at check time (not captured at init), so a live change
    // to `registry.hintFrequency` takes effect on the same gate without discarding
    // the session's "already shown" timestamps.
    @Test func policyIsEvaluatedPerCheckOnAPersistentGate() {
        var gate = HintPolicyGate()
        gate.markShown(actionID: "save")
        #expect(gate.shouldShow(actionID: "save", policy: .oncePerSession) == false)
        // Same gate, timestamp preserved — switching to .always shows again.
        #expect(gate.shouldShow(actionID: "save", policy: .always))
    }
}

// Test-only mutable clock helper.
private final class MutableClock: @unchecked Sendable {
    private var t: TimeInterval = 0
    func advance(by dt: TimeInterval) { t += dt }
    var now: @Sendable () -> Date { { [weak self] in Date(timeIntervalSince1970: self?.t ?? 0) } }
}
