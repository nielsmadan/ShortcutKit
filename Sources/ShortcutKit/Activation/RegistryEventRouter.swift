import AppKit
import ShortcutField

/// Routes events through active contexts from innermost to outermost.
///
/// The first fired match wins. Other matchers are reset so partial sequences
/// cannot affect later events.
@MainActor
final class RegistryEventRouter {
    private var stack: [any ContextMatching] = []
    private let dispatcher: ShortcutEventDispatcher
    private let listenerID = UUID()
    private var isRegistered = false

    init(dispatcher: ShortcutEventDispatcher = .shared) {
        self.dispatcher = dispatcher
    }

    func push(_ matcher: any ContextMatching) {
        stack.append(matcher)
        if !isRegistered {
            dispatcher.register(id: listenerID) { [weak self] event in
                self?.handle(event) ?? .ignored
            }
            isRegistered = true
        }
    }

    func remove(contextID: String) {
        stack.removeAll { $0.contextID == contextID }
        if stack.isEmpty, isRegistered {
            dispatcher.unregister(id: listenerID)
            isRegistered = false
        }
    }

    func handle(_ event: NSEvent) -> ShortcutMatchResult {
        var consumeFromAdvance = false
        var didAdvance = false
        for matcher in stack.reversed() {
            switch matcher.handle(event) {
            case .ignored:
                continue
            case let .advanced(consume):
                didAdvance = true
                consumeFromAdvance = consumeFromAdvance || consume
            case .fired:
                resetOthers(winner: matcher)
                return .fired
            case let .continuousFired(magnitude):
                resetOthers(winner: matcher)
                return .continuousFired(magnitude: magnitude)
            }
        }
        return didAdvance ? .advanced(consumeEvent: consumeFromAdvance) : .ignored
    }

    private func resetOthers(winner: any ContextMatching) {
        for matcher in stack where matcher !== winner {
            matcher.reset()
        }
    }

    // swiftlint:disable identifier_name
    func __setStackForTesting(_ matchers: [any ContextMatching]) {
        stack = matchers
    }

    var __currentStackIDs: [String] { stack.map(\.contextID) }
    // swiftlint:enable identifier_name
}
