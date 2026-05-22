@testable import ShortcutKit
import Testing

@MainActor
@Suite("ContinuousCoalescer") struct ContinuousCoalescerTests {
    @Test("accumulate then __flush dispatches once with the magnitude")
    func singleAccumulate() {
        let coalescer = ContinuousCoalescer()
        var received: Double?
        coalescer.accumulate(contextID: "viewer", actionID: "zoom-in", magnitude: 0.3) { m in
            received = m
        }
        coalescer.__flush()
        #expect(received == 0.3)
    }

    @Test("multiple accumulates on the same key sum into one dispatch")
    func sumsForSameKey() {
        let coalescer = ContinuousCoalescer()
        var received: Double?
        coalescer.accumulate(contextID: "viewer", actionID: "zoom-in", magnitude: 0.1) { _ in }
        coalescer.accumulate(contextID: "viewer", actionID: "zoom-in", magnitude: 0.3) { _ in }
        coalescer.accumulate(contextID: "viewer", actionID: "zoom-in", magnitude: 0.3) { m in
            received = m
        }
        coalescer.__flush()
        #expect(received == 0.7)
    }

    @Test("different keys dispatch independently")
    func independentKeys() {
        let coalescer = ContinuousCoalescer()
        var zoomIn: Double?
        var zoomOut: Double?
        coalescer.accumulate(contextID: "viewer", actionID: "zoom-in", magnitude: 0.2) { m in
            zoomIn = m
        }
        coalescer.accumulate(contextID: "viewer", actionID: "zoom-out", magnitude: -0.5) { m in
            zoomOut = m
        }
        coalescer.__flush()
        #expect(zoomIn == 0.2)
        #expect(zoomOut == -0.5)
    }

    @Test("flush clears pending — next flush is a no-op")
    func flushClears() {
        let coalescer = ContinuousCoalescer()
        var calls = 0
        coalescer.accumulate(contextID: "v", actionID: "a", magnitude: 0.1) { _ in calls += 1 }
        coalescer.__flush()
        coalescer.__flush()
        #expect(calls == 1)
    }

    @Test("a second accumulate-cycle after flush dispatches again")
    func secondCycle() {
        let coalescer = ContinuousCoalescer()
        var values: [Double] = []
        coalescer.accumulate(contextID: "v", actionID: "a", magnitude: 0.1) { values.append($0) }
        coalescer.__flush()
        coalescer.accumulate(contextID: "v", actionID: "a", magnitude: 0.5) { values.append($0) }
        coalescer.__flush()
        #expect(values == [0.1, 0.5])
    }
}
