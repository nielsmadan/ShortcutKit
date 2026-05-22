import Foundation
@testable import ShortcutKitUI
import Testing

@MainActor
struct HintPolicyTests {
    @Test func alwaysShowsEveryTime() {
        var gate = HintPolicyGate(policy: .always)
        #expect(gate.shouldShow(actionID: "save"))
        gate.markShown(actionID: "save")
        #expect(gate.shouldShow(actionID: "save"))
    }

    @Test func oncePerSessionShowsOnceThenSuppresses() {
        var gate = HintPolicyGate(policy: .oncePerSession)
        #expect(gate.shouldShow(actionID: "save"))
        gate.markShown(actionID: "save")
        #expect(gate.shouldShow(actionID: "save") == false)
        // Different action: not yet shown.
        #expect(gate.shouldShow(actionID: "new"))
    }

    @Test func timeoutSuppressesWithinWindow() {
        let clock = MutableClock()
        var gate = HintPolicyGate(policy: .timeout(0.1), now: clock.now)
        gate.markShown(actionID: "save")
        clock.advance(by: 0.05)
        #expect(gate.shouldShow(actionID: "save") == false)
        clock.advance(by: 0.1)
        #expect(gate.shouldShow(actionID: "save"))
    }
}

// Test-only mutable clock helper.
private final class MutableClock: @unchecked Sendable {
    private var t: TimeInterval = 0
    func advance(by dt: TimeInterval) { t += dt }
    var now: @Sendable () -> Date { { [weak self] in Date(timeIntervalSince1970: self?.t ?? 0) } }
}
