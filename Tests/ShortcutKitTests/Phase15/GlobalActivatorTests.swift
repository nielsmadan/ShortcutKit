@testable import ShortcutKit
import Testing

@MainActor
struct GlobalActivatorTests {
    final class FakeActivator: GlobalActivator {
        var started = false
        var status: [BindingID: GlobalBindingStatus] = [:]
        func start(_: ShortcutRegistry) throws { started = true }
        func stop() { started = false }
    }

    @Test func protocolShape() throws {
        let activator: any GlobalActivator = FakeActivator()
        try activator.start(ShortcutRegistry(contexts: []))
        activator.stop()
    }

    @Test func bindingIDIsHashable() {
        let a = BindingID(contextID: "ctx", actionID: "save", bindingIndex: 0)
        let b = BindingID(contextID: "ctx", actionID: "save", bindingIndex: 0)
        let c = BindingID(contextID: "ctx", actionID: "save", bindingIndex: 1)
        #expect(a == b)
        #expect(a != c)
        #expect(Set([a, b, c]).count == 2)
    }
}
