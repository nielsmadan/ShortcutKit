import AppKit
import Carbon.HIToolbox
import ShortcutField
@testable import ShortcutKit
import Testing

@MainActor
final class FakeContextMatcher: ContextMatching {
    let contextID: String
    var handleResult: (NSEvent) -> ShortcutMatchResult
    private(set) var resetCount = 0
    private(set) var rebuildCount = 0

    init(_ contextID: String,
         handle: @escaping (NSEvent) -> ShortcutMatchResult = { _ in .ignored })
    {
        self.contextID = contextID
        handleResult = handle
    }

    func handle(_ event: NSEvent) -> ShortcutMatchResult { handleResult(event) }
    func reset() { resetCount += 1 }
    func rebuild() { rebuildCount += 1 }
}

@MainActor
@Suite("RegistryEventRouter") struct RegistryEventRouterTests {
    private func keyDown(_ keyCode: Int = kVK_ANSI_S,
                         _ modifiers: NSEvent.ModifierFlags = .command) -> NSEvent
    {
        let cg = CGEvent(keyboardEventSource: nil,
                         virtualKey: CGKeyCode(keyCode), keyDown: true)!
        cg.flags = CGEventFlags(rawValue: UInt64(modifiers.rawValue))
        return NSEvent(cgEvent: cg)!
    }

    @Test("empty stack returns .ignored")
    func emptyStack() {
        let router = RegistryEventRouter()
        #expect(router.handle(keyDown()) == .ignored)
    }

    @Test("single context: result is forwarded")
    func singleContextForwards() {
        let inner = FakeContextMatcher("inner", handle: { _ in .fired })
        let router = RegistryEventRouter()
        router.__setStackForTesting([inner])
        #expect(router.handle(keyDown()) == .fired)
    }

    @Test("innermost wins: inner .fired pre-empts outer")
    func innermostWins() {
        let outer = FakeContextMatcher("outer", handle: { _ in .fired })
        let inner = FakeContextMatcher("inner", handle: { _ in .fired })
        let router = RegistryEventRouter()
        router.__setStackForTesting([outer, inner])
        #expect(router.handle(keyDown()) == .fired)
        #expect(outer.resetCount == 1)
        #expect(inner.resetCount == 0)
    }

    @Test(".advanced from inner does not pre-empt — outer still consulted")
    func advanceDoesNotPreempt() {
        let outer = FakeContextMatcher("outer", handle: { _ in .ignored })
        let inner = FakeContextMatcher("inner", handle: { _ in .advanced(consumeEvent: false) })
        let router = RegistryEventRouter()
        router.__setStackForTesting([outer, inner])
        #expect(router.handle(keyDown()) == .advanced(consumeEvent: false))
        #expect(outer.resetCount == 0)
        #expect(inner.resetCount == 0)
    }

    @Test("advance accumulates consumeEvent across contexts (any true wins)")
    func advanceAccumulatesConsume() {
        let outer = FakeContextMatcher("outer", handle: { _ in .advanced(consumeEvent: false) })
        let inner = FakeContextMatcher("inner", handle: { _ in .advanced(consumeEvent: true) })
        let router = RegistryEventRouter()
        router.__setStackForTesting([outer, inner])
        #expect(router.handle(keyDown()) == .advanced(consumeEvent: true))
    }

    @Test("on inner .fired, outer's prior advance is reset (no stuck state)")
    func outerResetOnInnerFire() {
        var outerStep = 0
        let outer = FakeContextMatcher("outer", handle: { _ in
            outerStep += 1
            return outerStep == 1 ? .advanced(consumeEvent: false) : .fired
        })
        let inner = FakeContextMatcher("inner", handle: { _ in .fired })

        let router = RegistryEventRouter()
        router.__setStackForTesting([outer, inner])

        #expect(router.handle(keyDown()) == .fired)
        #expect(outer.resetCount == 1)
    }

    @Test("inner .continuousFired pre-empts and resets outer")
    func continuousFiredPreempts() {
        let outer = FakeContextMatcher("outer", handle: { _ in .fired })
        let inner = FakeContextMatcher("inner", handle: { _ in .continuousFired(magnitude: 1.5) })
        let router = RegistryEventRouter()
        router.__setStackForTesting([outer, inner])
        #expect(router.handle(keyDown()) == .continuousFired(magnitude: 1.5))
        #expect(outer.resetCount == 1)
        #expect(inner.resetCount == 0)
    }
}
