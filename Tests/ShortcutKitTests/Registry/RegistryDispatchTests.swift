import Combine
@testable import ShortcutKit
import Testing

@MainActor
@Suite("RegistryDispatch") struct RegistryDispatchTests {
    enum Act: String, ShortcutAction {
        case save, undo
        var definition: ShortcutActionDefinition {
            switch self {
            case .save: .init("Save", "cmd+s")
            case .undo: .init("Undo", "cmd+z")
            }
        }
    }

    @Test("dispatch(ref) runs the handler and emits a .programmatic event")
    func dispatchRunsHandler() {
        var ran: [Act] = []
        let ctx = ShortcutContext<Act>(global: "editor") { action, _ in ran.append(action) }
        let registry = ShortcutRegistry(contexts: [ctx])
        var events: [ActionFiredEvent] = []
        let cancellable = registry.actionFired.sink { events.append($0) }

        registry.dispatch(ActionRef(contextID: "editor", actionID: "save"))

        #expect(ran == [.save])
        #expect(events.count == 1)
        #expect(events.first?.contextID == "editor")
        #expect(events.first?.actionID == "save")
        #expect(events.first?.source == .programmatic)
        _ = cancellable
    }

    @Test("the contextID:actionID: convenience routes the same way")
    func convenienceForwards() {
        var ran: [Act] = []
        let ctx = ShortcutContext<Act>(global: "editor") { action, _ in ran.append(action) }
        let registry = ShortcutRegistry(contexts: [ctx])

        registry.dispatch(contextID: "editor", actionID: "undo")

        #expect(ran == [.undo])
    }

    @Test("notify(ref) emits .programmatic without running the handler")
    func notifyDoesNotRun() {
        var ran = false
        let ctx = ShortcutContext<Act>(global: "editor") { _, _ in ran = true }
        let registry = ShortcutRegistry(contexts: [ctx])
        var events: [ActionFiredEvent] = []
        let cancellable = registry.actionFired.sink { events.append($0) }

        registry.notify(contextID: "editor", actionID: "save")

        #expect(ran == false)
        #expect(events.map(\.source) == [.programmatic])
        #expect(events.first?.actionID == "save")
        _ = cancellable
    }

    @Test("unknown context or action id is a silent no-op")
    func unknownIsNoOp() {
        var ran = false
        let ctx = ShortcutContext<Act>(global: "editor") { _, _ in ran = true }
        let registry = ShortcutRegistry(contexts: [ctx])
        var events: [ActionFiredEvent] = []
        let cancellable = registry.actionFired.sink { events.append($0) }

        registry.dispatch(contextID: "nope", actionID: "save") // unknown context
        registry.dispatch(contextID: "editor", actionID: "nope") // unknown action
        registry.notify(contextID: "nope", actionID: "save")

        #expect(ran == false)
        #expect(events.isEmpty)
        _ = cancellable
    }
}
